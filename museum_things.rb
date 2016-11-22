require 'twitter_ebooks'
require 'httparty'
require 'open-uri'

SEARCH_URI = 'http://collections.museumvictoria.com.au/api/search'

WITTY_RESPONSES = [
  'OK!',
  'Done!',
  'Alright!',
  'No worries.',
  'Cool!',
  'I painstakingly trawled the archives, and…'
]

UNSUCCESSFUL_RESPONSES = [
  "I tried my hardest, but couldn't find it. Here's something else.",
  "Here's what I'd rather do.",
  'How about this instead?',
  'This is kind of what you wanted, right?'
]

LICENSES = [
  'public domain',
  'cc by',
  'cc by-nc'
]

class MuseumThingsBot < Ebooks::Bot
  class NoRecordFound < Exception; end

  def configure
    # Consumer details come from registering an app at https://dev.twitter.com/
    # Once you have consumer details, use "ebooks auth" for new access tokens
    self.consumer_key = '' # Your app consumer key
    self.consumer_secret = '' # Your app consumer secret

    # Range in seconds to randomize delay when bot.delay is called
    self.delay_range = 0..600
  end

  def get_something_to_tweet(query = nil)
    # We have to pick a license first because you can't search for things with _one of_ the specified licenses
    imagelicence = LICENSES.sample

    log "Getting something #{imagelicence} to Tweet..."
    if !query.nil? then
      log "(Query is \"#{query}\")"
    end
    meta_response = HTTParty.get SEARCH_URI, query: { hasimages: 'yes', imagelicence: imagelicence, page: 10000000, query: query }

    log "Fetched #{meta_response.request.last_uri.to_s}"

    total_items = meta_response.headers['total-results'].to_i
    total_pages = meta_response.headers['total-pages'].to_i

    if !query.nil? && total_items == 0 then
      log "Nothing found..."
      raise NoRecordFound, "Nothing found for query '#{query}'"
    end

    log "Got initial pagination request. #{total_items} items on #{total_pages} pages."

    select_item = Random.rand total_items
    select_page = (select_item / 40).floor
    index_on_page = select_item % 40

    log "Seeking to page ##{select_page} for item #{select_item} (will be ##{index_on_page} on page)..."

    items_response = HTTParty.get SEARCH_URI, query: { hasimages: 'yes', imagelicence: imagelicence, page: select_page, query: query }

    log "Fetched #{items_response.request.last_uri.to_s}"

    selected_thing = items_response[index_on_page];

    thing_name = selected_thing['title'] || selected_thing['objectName']
    thing_image = selected_thing['media'].select{|media| !media['caption'].nil? && !media['large'].nil?}.sample
    thing_image_uri = thing_image['large']['uri']

    if thing_name.nil? || thing_image['caption'].length > thing_name.length then
      thing_name = thing_image['caption'];
    end

    if thing_name.nil? then
      log "Weird... thing doesn't have any name I could find (#{selected_thing['id']})! Trying again..."
      # Try again!
      return get_something_to_tweet
    end

    # Strip HTML
    thing_name = thing_name.gsub(/<\/?[^>]*>/, "")

    log "Thing is #{selected_thing['id']}, #{thing_name}, image at #{thing_image_uri}."

    thing_tweet = "#{thing_name} http://collections.museumvictoria.com.au/#{selected_thing['id']}"

    [thing_tweet, open(thing_image_uri)]
  end

  def make_public_tweet(query = nil)
    text, image = get_something_to_tweet(query)
    id = twitter.upload(image).to_s
    tweet(text, {media_ids: id})
  end

  # def on_follow(user)
  #   follow(user.screen_name)
  # end

  def on_message(dm)
    begin
      tweet = make_public_tweet(dm.text)
      reply(dm, "#{WITTY_RESPONSES.sample} It's up at #{tweet.uri}")
    rescue NoRecordFound
      tweet = make_public_tweet()
      reply(dm, "#{UNSUCCESSFUL_RESPONSES.sample} It's up at #{tweet.uri}")
    end
  end

  def on_startup
    scheduler.every '43m' do
      delay do
        make_public_tweet
      end
    end
  end

  # def on_mention(tweet)
  #   text, image = get_something_to_tweet(meta(tweet).mentionless)
  #   id = twitter.upload(image).to_s
  #   reply(tweet, text, {media_ids: id})
  # end
end

MuseumThingsBot.new("museum_things") do |bot|
  bot.access_token = "" # Token connecting the app to this account
  bot.access_token_secret = "" # Secret connecting the app to this account
end
