# HandshakeService

A collection of rake tasks and libraries commonly used in Handshake services.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'handshake_service'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install handshake_service

## Usage

## LibratoHelper

Use LibratoHelper as a wrapper around Librato for sanitizing key names and simplifying the API. Examples:

```HandshakeService::LibratoHelper.increment 'handshake_office.doc_to_pdf.count'```
```HandshakeService::LibratoHelper.measure 'handshake_office.doc_to_pdf.timing'```

## deploy:<env>

TODO: write me

## deploy:<env>:migrations

TODO: write me

## deploy:<env>:preboot

TODO: write me

## Other rake tasks

TODO: Write me

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/strydercorp/handshake_service.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

