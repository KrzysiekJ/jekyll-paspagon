# -*- coding: utf-8 -*-

class PaspagonConfig
  attr_reader :buckets, :formats, :full_config

  def initialize(site)
    @site = site
    @full_config = site.config['paspagon'] || {}
    @terms_accepted = @full_config['accept-terms'] == 'https://github.com/Paspagon/paspagon.github.io/blob/master/terms-seller.md'
    raise 'Paspagon terms not accepted' unless @terms_accepted
    @buckets = @full_config['buckets'] || {}
    @formats = @full_config['formats'] || {}
  end

  def post_config_complete(post)
    payment_config = full_payment_config post
    prices(payment_config) && addresses(payment_config)
  end

  def bucket_name(post)
    bucket = post.data['bucket']
    raise 'Bucket not specified for post' unless bucket
    raise "Bucket not found: #{bucket}" unless @buckets.key?(bucket)
    bucket
  end

  def format_configs(post)
    @formats.merge(post.data['formats'] || {})
  end

  def paid_dest_dir
    File.join(@site.dest, '../_paid')
  end

  def bucket_dest_dir(bucket_name)
    File.join(paid_dest_dir, bucket_name)
  end

  def write_buckets_config
    @buckets.each do |bucket_name, bucket_hash|
      bucket_config = bucket_hash.update('accept-terms' => @full_config['accept-terms'])
      ini = hash_to_ini bucket_config
      dest = File.join(bucket_dest_dir(bucket_name), 'paspagon.ini')
      ini_hash = Digest::SHA256.digest(ini)
      next if File.exist?(dest) && Digest::SHA256.file(dest).digest == ini_hash
      File.open(dest, 'wb') do |f|
        f.write(ini)
      end
    end
  end

  def logging_bucket_name
    @full_config['logging_bucket']
  end
end

def hash_to_ini(hash, section = nil, section_nested = nil)
  sections, entries = hash.partition { |_, v| v.is_a? Hash }
  lines = []
  lines += ["[#{section}]"] if section && !section_nested
  section_prefix = section_nested ? "#{section}-" : ''
  lines += entries.map { |e| section_prefix + e.join(' = ') }
  lines += sections.map do |inner_section, inner_section_entries|
    hash_to_ini(inner_section_entries, section_prefix + inner_section, section)
  end
  lines.flatten.join("\n")
end
