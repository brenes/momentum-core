$KCODE = "u"
require 'rubygems'
require 'time'
require 'twitter/json_stream'
require 'vendor/em-couchdb/lib/em-couchdb'
require 'rake'
require "twitter-text"
include Twitter::Extractor

settings = YAML::load( File.open( 'settings.yml' ) )

namespace :tweets do

	desc "Collects JSON tweets from the Twitter Streaming API, and stores the mentions on CouchDB"
	task :collect do 
		EventMachine::run {
		  stream = Twitter::JSONStream.connect(
		    :path    => "/1/statuses/filter.json?track=#{settings["twitter"]["track_word"]}",
		    :auth    => "#{settings["twitter"]["username"]}:#{settings["twitter"]["password"]}'
		  )
		  couch = EventMachine::Protocols::CouchDB.connect :host => 'localhost', :port => 5984, :database => 'twitter-stream'
		  stream.each_item do |item|
			begin
				# we parse the tweet, extract the mentions and store them
				tweet = JSON.parse item
				usernames = extract_mentioned_screen_names(tweet["text"])
				extract_reply_screen_name(tweet["text"]) do |user|
					usernames << user
				end
				unless usernames.empty? 
					couch.save('tweets2', JSON.parse(item)) do end
					usernames.each do |user|
						couch.save('mentions', :user => user, :created_at => tweet["created_at"]) do end
					end
				end
			rescue Exception => ex
				puts "NO JSON: #{ex}"
			end
		  end
		}
	end


end
