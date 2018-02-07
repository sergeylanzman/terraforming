module Terraforming
  module Resource
    class S3
      include Terraforming::Util

      def self.tf(client: Aws::S3::Client.new)
        self.new(client).tf
      end

      def self.tfstate(client: Aws::S3::Client.new)
        self.new(client).tfstate
      end

      def initialize(client)
        @client = client
      end

      def tf
        apply_template(@client, "tf/s3")
      end

      def tfstate
        buckets.inject({}) do |resources, bucket|
          bucket_policy = bucket_policy_of(bucket)
          resources["aws_s3_bucket.#{module_name_of(bucket)}"] = {
              "type" => "aws_s3_bucket",
              "primary" => {
                  "id" => bucket.name,
                  "attributes" => {
                      "acl" => "private",
                      "bucket" => bucket.name,
                      "force_destroy" => "false",
                      "id" => bucket.name,
                      "policy" => bucket_policy ? bucket_policy : "",
                  }
              }
          }

          resources
        end
      end

      private

      def bucket_location_of(bucket)
        @client.get_bucket_location(bucket: bucket.name).location_constraint
      end

      def bucket_policy_of(bucket)
        bucket.policy.policy.read
      rescue Aws::S3::Errors::NoSuchBucketPolicy
        nil
      end

      def buckets
        return @buckets unless @buckets.nil?
        @buckets = []
        @client.list_buckets.map(&:buckets).flatten.each do |bucket|
          if same_region?(bucket)
            @buckets << Aws::S3::Bucket.new(bucket.name, client: @client)
          end
        end
        @buckets
      end

      def module_name_of(bucket)
        normalize_module_name(bucket.name)
      end

      def has_tagging?(bucket)
        if bucket.tagging.tag_set.nil?
          return false
        end
        true
      rescue Aws::S3::Errors::NoSuchTagSet
        false
      end

      def has_cors?(bucket)
        if bucket.cors.cors_rules.nil?
          return false
        end
        true
      rescue Aws::S3::Errors::NoSuchCORSConfiguration
        false
      end

      def has_lifecycle?(bucket)
        if bucket.lifecycle_configuration.rules.nil?
          return false
        end
        true
      rescue Aws::S3::Errors::NoSuchLifecycleConfiguration
        false
      end

      def has_website_configuation?(bucket)
        if bucket.website.index_document.nil?
          return false
        end
        true
      rescue Aws::S3::Errors::NoSuchWebsiteConfiguration
        false
      end

      def prettify_website_routing_rules(bucket)
        prettify_policy(bucket.website.routing_rules.map{|t| (t.to_h).to_json}.to_json.gsub('"{','{').gsub('\"','"').gsub('}"','}'))
      end

      def same_region?(bucket)
        bucket_location = bucket_location_of(bucket)
        (bucket_location == @client.config.region) || (bucket_location == "" && @client.config.region == "us-east-1")
      end
    end
  end
end
