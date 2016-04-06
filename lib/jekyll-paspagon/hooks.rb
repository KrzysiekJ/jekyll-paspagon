# -*- coding: utf-8 -*-
require 'fileutils'
require 'tmpdir'
require 'ffi-xattr'
require 'jekyll-paspagon/config'

Jekyll::Hooks.register :site, :pre_render do |site|
  config = PaspagonConfig.new(site)
  site.exclude << '_paid' unless site.exclude.include?('_paid')
  site.posts.docs.each do |post|
    post.data['formats'] ||= {}
    # Jekyll does not do a simple merge of default values with post values, so
    # we cannot unset default formats in an ordinary way. Instead, we reject null values.
    post.data['formats'] = post.data['formats'].reject { |_, v| !v }
    prices = post.data['price'] || {}
    addresses = post.data['address'] || {}
    link_expiration_time = post.data['link-expiration-time'] || nil
    config.format_configs(post).each do |format, format_config|
      paid = format_paid? post, format_config
      format_dest_dir =
        if paid
          bucket_name = config.bucket_name post
          File.dirname(File.join(config.bucket_dest_dir(bucket_name), post.url))
        else
          File.dirname(File.join(site.dest, post.url))
        end
      post_basename = File.basename(post.url)
      format_filename = "#{post_basename}.#{format}"
      format_dest = File.join(format_dest_dir, format_filename)
      format_url_ending =
        if format == 'html' && !paid
          post.url
        else
          File.join(File.dirname(post.url), format_filename)
        end
      format_url =
        if paid
          bucket_name = config.bucket_name post
          "https://s3-us-west-2.paspagon.com/#{bucket_name}#{format_url_ending}"
        else
          "#{site.config['url']}#{site.config['baseurl']}#{format_url_ending}"
        end

      format_info =
        {'paid' => paid,
         'post' => post,
         'path' => format_dest,
         'full_url' => format_url,
         'link_expiration_time' => link_expiration_time,
         'prices' => prices,
         'name' => format.upcase,
         'addresses' => addresses}
      post.data['formats'][format] = post.data['formats'][format].merge(format_info)
      post.data['format_array'] = post.data['formats'].map { |_, v| v }
    end
  end

  config.write_buckets_config
end

Jekyll::Hooks.register :posts, :post_write do |post|
  unless post.data['excerpt_only']
    post.data['formats'].each do |format, format_config|
      puts("Generated #{format_config['path']}.") if maybe_generate_doc(post, format)
      attrs = format_xattrs(format, format_config)
      sync_payment_attributes(format_config['path'], attrs)
    end
  end
end

def format_xattrs(format, format_config)
  attrs = {}
  format_config['prices'].each do |currency, price|
    attrs["user.x-amz-meta-price-#{currency}"] = price if price
  end
  format_config['addresses'].each do |currency, address|
    attrs["user.x-amz-meta-address-#{currency}"] = address if address
  end
  attrs['user.x-amz-meta-link-expiration-time'] = format_config['link_expiration_time'] if format_config['link_expiration_time']
  attrs['user.content-disposition'] = format_config['content_disposition'] if format_config['content_disposition']
  attrs['user.content-type'] = format_config['content_type'] || default_content_type(format)
  attrs
end

def default_content_type(format)
  content_types =
    {'epub' => 'application/epub+zip',
     'html' => 'text/html',
     'mobi' => 'application/x-mobipocket-ebook',
     'pdf' => 'application/pdf'}
  content_types.default = 'application/octet-stream'
  content_types[format]
end

def sync_payment_attributes(path, attrs)
  xattr = Xattr.new(path)
  old = xattr.list.select { |a| a.start_with?('user.') }
  new = attrs.keys
  (old - new).each do |a|
    xattr.remove a
  end
  new.each do |a|
    xattr[a] = attrs[a] unless xattr[a] == attrs[a].to_s
  end
end

def maybe_generate_doc(post, format)
  format_config = post.data['formats'][format]
  dest_path = format_config['path']
  FileUtils.mkdir_p(File.dirname(dest_path))
  if File.exist?(dest_path)
    source_path = post.path
    if File.ctime(source_path) > File.ctime(dest_path)
      temp_path = File.join(Dir.tmpdir, Digest::SHA256.hexdigest(dest_path) + '.' + format)
      generate_doc(post, format, format_config, temp_path)
      temp_hash = Digest::SHA256.file(temp_path)
      dest_hash = Digest::SHA256.file(dest_path)
      if temp_hash == dest_hash
        # Unfortunately, this check usually doesn’t yield desired effect, as Pandoc’s conversion to EPUB is impure.
        File.delete(temp_path)
        false
      else
        FileUtils.mv(temp_path, dest_path)
        true
      end
    else
      false
    end
  else
    generate_doc(post, format, format_config, dest_path)
    true
  end
end

def generate_doc(post, format, format_config, dest_path)
  case format
  when 'html'
    if format_config['paid']
      free_dest = post.destination
      system("mv #{free_dest} #{dest_path}")
      post.content = post.data['excerpt'].output
      post.data['excerpt_only'] = true
      post.output = Jekyll::Renderer.new(post.site, post, post.site.site_payload).run
      # We don’t use post.write method to not trigger infinite hook recursion.
      File.open(free_dest, 'wb') do |f|
        f.write(post.output)
      end
    end # If HTML format is free, then it is already generated, so we don’t need to do anything.
  else
    command = generation_command(post, format, format_config, dest_path)
    raise "Failed to execute: #{command}" unless system command
  end
end

def generation_command(post, format, _format_config, dest_path)
  input_format = pandoc_input_format(post.site)
  case format
  when 'azw3', 'mobi', 'pdf'
    intermediary_path = File.join(Dir.tmpdir, Digest::SHA256.hexdigest(dest_path) + '.epub')
    "pandoc #{post.path} -f #{input_format} -t epub -o #{intermediary_path} && ebook-convert #{intermediary_path} #{dest_path} --start-reading-at \"//h:h1[not(contains (@class, 'title'))]\" > /dev/null && rm #{intermediary_path}"
  else
    "pandoc #{post.path} -f #{input_format} -t #{format} -o #{dest_path}"
  end
end

def pandoc_input_format(site)
  (site.config['pandoc'] || {})['input'] ||
    begin
      kramdown = site.config['kramdown'] || {}
      format = 'markdown_github+yaml_metadata_block'
      format += '-hard_line_breaks' unless kramdown['hard_wrap']
      format
    end
end

def format_paid?(post, format_config)
  too_late =
    if format_config['paid_before']
      Date.today - Date.parse(post.date.to_s) >= format_config['paid_before'].to_i
    else
      false
    end
  too_soon =
    if format_config['paid_after']
      Date.today - Date.parse(post.date.to_s) <= format_config['paid_after'].to_i
    else
      false
    end
  !too_late && !too_soon
end
