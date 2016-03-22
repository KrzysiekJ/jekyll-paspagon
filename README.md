# jekyll-paspagon

This [Jekyll](http://jekyllrb.com) plugin allows you to sell blog posts in various formats (HTML, EPUB, AZW3, MOBI, PDF and more) for [Bitcoin](https://bitcoin.org) and [BlackCoin](http://blackcoin.co), using Amazon S3 and [Paspagon](http://paspagon.com).

## Installation

### Install dependencies

If you want to sell posts in formats other than HTML, [install Pandoc](http://pandoc.org/installing.html). If you want to sell MOBI, AZW3 or PDF files, install [Calibre](https://calibre-ebook.com/).

### Install plugin

Add the `jekyll-paspagon` gem to the `:jekyll_plugins` group in your `Gemfile`:

```ruby
group :jekyll_plugins do
  gem 'jekyll-paspagon', '~>1'
end
```

### Configure Paspagon

To your `_config.yml`, add a section adhering to the following example:

```yaml
paspagon:
  # By making this entry, you indicate that you accept Paspagon’s terms of
  # service. Be sure that you’ve actually read these terms!
  accept-terms: https://github.com/Paspagon/paspagon.github.io/blob/master/terms-seller.md
  buckets:
    your-bucket-name:
      seller:
        country-code: PL
        email: john.doe@example.com # Email is optional
      payment:
        # This section provides default values that you can override for each post.
        #
        # You can specify prices in BTC, BLK, XAU (troy ounce of gold) and some
        # other currencies (see Paspagon’s terms of service for a complete list).
        # (Paspagon takes only one price into account).
        price:
          USD: 3
        address:
          BTC: 1your-address
          BLK: Byour-address
        # Time (in seconds) after which download link will expire.
        link-expiration-time: 600
  # A name of a bucket which will be used to store S3 request logs.
  logging_bucket: paspagon-logs-foo
```

### Set default post configuration

Add the bucket and formats configuration to the `default` section in your `_config.yml`. This is optional, but handy.

```yaml
defaults:
  - scope:
      path: ""
    values:
      formats:
        # This section provides default values that you can override for each post.
        html:
          paid_after: 15 # HTML version will be paid 15 days after publication.
        pdf:
          content_disposition: attachment
          content_type: application/pdf
          paid_before: 2 # PDF version will be paid for the first two days.
        epub: {} # EPUB version will be paid from the beginning.
      bucket: your-bucket-name
```

Caveat: “default” values in Jekyll are actually not default values that can be simply overridden. Instead they get “deep merged” into post variables. If you want to unset a specific nested value inside the `formats` hash, set it to `false`.

### Change post template

Inform your readers that you offer alternate post formats by modifying the post template. In a simple form the relevant fragment may look like this:

```liquid
{% unless page.formats == empty %}
  <p>Available formats:
    {% for format in page.format_array %}
      <a href="{{ format.full_url }}">{{ format.name }}</a>{% unless forloop.last %},{% endunless %}
    {% endfor %}
  </p>
{% endunless %}
```

A more sophisticated example, which uses the `page.excerpt_only` variable (set only when HTML is a paid format and a summary is being rendered):

```liquid
{% unless page.formats == empty %}
  <p>
    {% if page.excerpt_only %}
      Available formats:
    {% else %}
      Alternate formats:
    {% endif %}
    {% for format in page.format_array %}
      {% if format.name != 'HTML' or page.excerpt_only %}
        <a {% if format.paid %}class="paid" {% endif %}href="{{ format.full_url }}">{{ format.name }}</a>{% unless forloop.last %},{% endunless %}
      {% endif %}
    {% endfor %}
  </p>
{% endunless %}
```

### Change feed template

If you provide a RSS/Atom feed, you may want to ensure that it contains only post excerpts instead of complete contents. Typically, you will need to change `{{ post.content | xml_escape }}` to `{{ post.excerpt | xml_escape }}` in your `feed.xml` template.

### Generate full URLs everywhere

If you’re going to sell HTML versions of your posts (which will be hosted on a different domain), you should ensure that links on your website contain the domain. The easiest way to do it is to remove all occurences of `site.url` from the templates (usually in `feed.xml` and `_includes/head.html`) and add the domain to the `baseurl` setting.

## Usage

After doing the steps above, paid versions of your posts will be generated automatically.

If you specify thresholds like `paid_before`, you will need to run `jekyll build` again after reaching them.

You may override formats, assigned buckets, prices, payment addresses and link expiration times for each post by putting the relevant data in the YAML front matter:

```yaml
layout: post
title: Foo
payment:
  price:
    USD: false
    XAU: 3
  address:
    BTC: 1Foo
bucket: foo
formats:
  epub:
    paid_after: 15
  pdf:
    # Setting this to false means that a post will be paid from the beginning.
    # If you want a format to be free instead, set this to 0.
    paid_before: false
  azw3: {}
```

Two Jekyll subcommands are available to synchronize paid content with Amazon S3. You need to [specify AWS credentials](http://blogs.aws.amazon.com/security/post/Tx3D6U6WSFGOK2H/A-New-and-Standardized-Way-to-Manage-Credentials-in-the-AWS-SDKs) beforehand.

### paspagon_prepare

This command creates necessary buckets, configures logging and log expiration (to 90 days) and sets permissions for Paspagon. It typically needs to be executed only once, after configuring Paspagon.

### paspagon_sync

This command uploads missing or updated paid files to S3 and removes ones which are not present locally. It should be ran each time a blog content update is deployed.

## Markdown compatibility

jekyll-paspagon uses Pandoc to generate formats other than HTML. The default input format is `markdown_github-hard_line_breaks`. It may be impacted by some site settings like Kramdown’s `hard_wrap`, but the most reliable way of changing it is setting it explicitly in `_config.yml`:

```yaml
pandoc:
  input: markdown_phpextra-fenced_code_blocks+strikeout
```

For more information, refer to [Pandoc’s documentation on Markdown](http://pandoc.org/README.html#pandocs-markdown).

## Versioning

This project uses [semantic versioning](http://semver.org/).

## License

This software is licensed under [the MIT License](LICENSE).
