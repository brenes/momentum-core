$KCODE = "u"
require 'rubygems'
require 'time'
require 'twitter/json_stream'
require 'vendor/em-couchdb/lib/em-couchdb'
require 'rake'
require "twitter-text"
require "twitter"
require "couchrest"
require "couchrest_model"
require "hoptoad_notifier"
include Twitter::Extractor

require './models/mention.rb'
require './models/user.rb'
require './models/period_report.rb'

settings = YAML::load( File.open( 'settings.yml' ) )

HoptoadNotifier.configure do |config|
  config.api_key = settings["hoptoad"]["api_key"] 
end

namespace :tweets do

	desc "Collects JSON tweets from the Twitter Streaming API, and stores the mentions on CouchDB"
	task :collect do

	begin  
		EventMachine::run {
		  stream = Twitter::JSONStream.connect(
		    :path    => "/1/statuses/filter.json?track=#{settings["twitter"]["track_word"]}",
		    :auth    => "#{settings["twitter"]["username"]}:#{settings["twitter"]["password"]}"
		  )
		  couch = EventMachine::Protocols::CouchDB.connect :host => 'localhost', :port => 5984, :database => 'twitter-stream'
		  stream.each_item do |item|
			begin
				tweet = JSON.parse item
				usernames = extract_mentioned_screen_names(tweet["text"])
				extract_reply_screen_name(tweet["text"]) do |user|
					usernames << user
				end
				unless usernames.empty? 
				puts "#{Time.now} #{usernames.length} mentions accepted"
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
	rescue Exception => ex
		hoptoad_notify "An error has happened while gathering tweets: #{ex}"
	end
	end

	desc "Calculates accelerations for previous hour and stores them on users profile"
	task :summarize do 
	begin		
		# time_query = Time.now.strftime("%Y %b %d %H")
		time_query = "2010 Dec 08 20"
		puts "Looking for mentions on #{time_query}"

		mentions =  Mention.view "by_hour", :key => time_query, :raw => true
	
		users = {}
		total_mentions = mentions["rows"].length
		followers = 0
		users_with_followers = 0

		#we group the mentions by each user
		mentions["rows"].each do |mention|	
			user = mention["value"].downcase
			users[user] ||= User.find "u_#{user}"
			users[user] ||= User.new :_id => "u_#{user}", :nickname => user
			unless  not(users[user].reports.last.blank?) and users[user].reports.last.time == time_query
				users[user].reports << UserReport.new
				users[user].reports.last.time = time_query
				users[user].reports.last.mentions ||= 0
			end
			users[user].reports.last.mentions += 1
		end

		#we calculate aceleration, obtain the user, calculate velocity and store the info
				
		puts "sorting users"

		# Now we get a list of users sorted by the number of mentions
		top_users = {}
		users.each do |user, info|
			n_mentions = info.reports.last.mentions
			top_users[n_mentions] ||= []
			top_users[n_mentions] << user
		end

		puts "Getting Twitter Info"

		# Now we get the followers number for the most mentioned users
		api_requests = 0
		begin
			top_users.sort.reverse.first(2).each do |mentions, mentioned_users|
				mentioned_users.each do |user|
					begin
						unless not(users[user].profiles.last.blank?) and users[user].profiles.last[:time] == time_query
							puts "Retrieving info for #{user}"
							twitter_profile = Twitter::Client.new.user(user)
							users[user].profiles << JSON.parse(twitter_profile.to_json)
							users[user].profiles.last[:time] = time_query
						end
						followers += users[user].profiles.last["followers_count"] 
						users_with_followers += 1
					rescue Twitter::NotFound => ex
						puts "User not found: #{ex}"
					end
				end
			end
		rescue	Exception => ex
			puts "Twitter API LIMIT exceeded #{ex}"
			raise ex
		end

		puts "Computing velocity"

		# Now, with twitter info we shoud be able to compute Phi. We need:
		# The average number of mentions per hour (for now, the mentions in this period)
		average_mentions = total_mentions
		# Number of users
		total_users = users.length
		# The average number of followers for a user (taken from the profiles just collected)
		average_followers = followers / users_with_followers.to_f
		phi = (average_mentions / total_users) / average_followers
		
		puts "mentions: #{average_mentions}"
		puts "users: #{total_users}"
		puts "followers: #{average_followers}"
		puts "phi: #{phi}" 	

		# And now we compute the velocity for all the users

		accelerated_users = {}
		total_acceleration = 0
		total_velocity = 0

		users.each do |user, profile|
			report = profile.reports.last
			previous_report = profile.reports[-2]
			followers = (report.followers == 0) ? average_followers : report.followers

			report.acceleration = (report.mentions / followers.to_f) - phi
			total_acceleration += report.acceleration
			report.velocity = (previous_report.blank? ? 0 : previous_report.velocity) + report.acceleration
			total_velocity += report.velocity

			accelerated_users[report.acceleration] ||= []
			accelerated_users[report.acceleration] << user

		end
		puts "saving"

		period_report = PeriodReport.find(time_query) || PeriodReport.new(:_id => time_query)
		period_report.mentions = total_mentions
		period_report.average_followers =  average_followers
		period_report.average_acceleration = total_acceleration / users.length
		period_report.average_velocity = total_velocity / users.length
		period_report.sorted_users = accelerated_users.sort.reverse.map{|acceleration, a_users| a_users}.flatten
		period_report.save

		users.each { |user, info| info.save }
	rescue Exception => ex
		hoptoad_notify "An error has happened while summarizing mentions: #{ex}"
		raise ex				
	end
	end
end
