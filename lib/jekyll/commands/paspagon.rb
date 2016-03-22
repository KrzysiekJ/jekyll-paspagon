# -*- coding: utf-8 -*-
require 'aws-sdk-resources'
require 'ffi-xattr'
require 'jekyll-paspagon/config'

module Jekyll
  module Commands
    class Paspagon < Command
      class << self
        def init_with_program(jekyll)
          client = Aws::S3::Client.new(region: 'us-west-2')
          jekyll.command(:paspagon_prepare) do |c|
            c.syntax 'paspagon_prepare'
            c.description 'Create and configure S3 buckets for Paspagon'

            c.action do |_, options|
              site_options = configuration_from_options(options)
              site = Jekyll::Site.new(site_options)
              config = PaspagonConfig.new(site)

              logging_bucket_name = config.logging_bucket_name
              logging_bucket = ensure_logging_bucket(logging_bucket_name, client) if logging_bucket_name
              config.buckets.keys.each do |bucket_name|
                prepare_bucket(bucket_name, client, logging_bucket)
              end
            end
          end

          jekyll.command(:paspagon_sync) do |c|
            c.syntax 'paspagon_sync'
            c.description 'Sync paid files with S3'

            c.action do |_, options|
              site_options = configuration_from_options(options)
              site = Jekyll::Site.new(site_options)
              config = PaspagonConfig.new(site)

              paid_dir = config.paid_dest_dir
              Dir["#{paid_dir}/*/"].each do |dir|
                sync_path(dir, client)
              end
            end
          end
        end

        def prepare_bucket(name, client, logging_bucket)
          bucket = Aws::S3::Bucket.new(name, client: client)
          bucket.create unless bucket.exists?
          policy = <<-JSON
{
  "Version": "2012-10-17",
  "Statement": {
    "Resource": "arn:aws:s3:::#{name}/*",
    "Sid": "PaspagonAllow",
    "Effect": "Allow",
    "Principal": {"AWS": "154072225287"},
    "Action": ["s3:GetObject"]
  }
}
 JSON
          client.put_bucket_policy(bucket: name, policy: policy)
          logging_status =
            {logging_enabled:
             {target_bucket: logging_bucket.name,
              target_prefix: "#{name}/"}}
          client.put_bucket_logging(bucket: name, bucket_logging_status: logging_status)
        end

        def ensure_logging_bucket(name, client)
          bucket = Aws::S3::Bucket.new(name: name, client: client)
          bucket.create unless bucket.exists?
          lifecycle_configuration =
            {rules:
             [{expiration:
               {days: 90},
               prefix: '',
               status: 'Enabled'
              }]}
          client.put_bucket_lifecycle_configuration(bucket: name, lifecycle_configuration: lifecycle_configuration)
          client.put_bucket_acl(bucket: name, acl: 'log-delivery-write')
          bucket
        end

        def sync_path(path, client)
          Dir.chdir(path) do
            local_files =
              Dir.glob('**/*').select { |p| File.file?(p) }.map { |p| [p, [File.mtime(p), File.ctime(p)].max] }.to_h

            bucket_name = File.basename(path)
            bucket = Aws::S3::Bucket.new(bucket_name, client: client)
            cloud_files = bucket.objects.map { |o| [o.key, o.last_modified] }.to_h

            to_delete = (cloud_files.keys - local_files.keys)
            unless to_delete.empty?
              puts('Deleting objects:')
              to_delete.each do |p|
                puts("\t#{p}")
              end
              bucket.delete_objects(delete: {objects: to_delete.map { |p| {key: p} }})
            end

            to_upload = local_files.keys.select { |p| !cloud_files[p] || local_files[p] > cloud_files[p] }
            to_upload.each do |p|
              puts("Uploading #{p} to bucket #{bucket_name}…")
              xattr = Xattr.new(p)
              metadata = xattr.as_json.select { |k, _| k.start_with?('user.') }.map { |k, v| [k.sub(/^user./, ''), v] }.to_h
              bucket.put_object(body: File.open(p),
                                metadata: metadata,
                                key: p)
            end
          end
        end
      end
    end
  end
end
