$KCODE = "u"
require 'rubygems'
require 'time'
require 'twitter/json_stream'
require './vendor/em-couchdb/lib/em-couchdb'
require 'rake'
require "twitter"
require "couchrest"
require "couchrest_model"
require "hoptoad_notifier"

require './models/tweet.rb'
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
				tweet = Tweet.from_hash JSON.parse(item)
				usernames = tweet.mentioned_users
				unless usernames.empty? 
				puts "#{Time.now} #{usernames.length} mentions accepted"
					couch.save('tweets', tweet.to_json_object) do end
				end
			rescue Exception => ex
				puts "NO JSON: #{ex}"
			end
		  end
  
		stream.on_error do |message|
  			HoptoadNotifier.notify Exception.new("Streaming API Error: #{message}")
		end

  		stream.on_max_reconnects do |timeout, retries|
			HoptoadNotifier.notify Exception.new("Max Reconnects Error: #{message}")

  		end
		}
	rescue Exception => ex
		HoptoadNotifier.notify ex
	end
	end

	desc "Calculates accelerations for previous hour and stores them on users profile"
	task :summarize do 
	begin		
		time_query = 1.hour.ago.strftime("%Y %b %d %H")
		#time_query = Time.now.strftime("%Y %b %d %H")
		#time_query = "2010 Dec 08 20"
		time_key = 1.hour.ago.strftime("%Y%m%d%H")

		puts "Looking for mentions on #{time_query}"

		tweets =  Tweet.view "by_hour", :key => time_query
	
		users = {}
		total_mentions = 0
		followers = 0
		users_with_followers = 0

		#we group the mentions by each user
		tweets.each do |tweet|	
			mentioned_users = tweet.mentioned_users
			total_mentions += mentioned_users.length
			mentioned_users.each do |user|
				users[user] ||= User.find "u_#{user}"
				users[user] ||= User.new :_id => "u_#{user}", :nickname => user
				users[user].reports ||= {}
				if users[user].reports[time_key].blank?
					users[user].reports[time_key] = UserReport.new :time => time_key
				end
				users[user].reports[time_key].mentions += 1
			end
		end

		#we calculate aceleration, obtain the user, calculate velocity and store the info
				
		puts "sorting users"

		# Now we get a list of users sorted by the number of mentions
		top_users = {}
		users.each do |user, info|
			n_mentions = info.reports[time_key].mentions
			top_users[n_mentions] ||= []
			top_users[n_mentions] << user
		end

		puts "Getting Twitter Info"

		# Now we get the followers number for the most mentioned users
		api_requests = 0
		begin
			top_users.sort.reverse.each do |mentions, mentioned_users|
				mentioned_users.each do |user|
					begin
						if users[user].profile.blank?
							puts "Retrieving info for #{user}"
							twitter_profile = Twitter::Client.new.user(user)
							users[user].profiles << JSON.parse(twitter_profile.to_json)
							users[user].profiles.last[:time] = time_query
						end
						followers += users[user].profile["followers_count"] 
						users_with_followers += 1
					rescue Twitter::NotFound => ex
						puts "User not found: #{ex}"
					end
				end
			end
		rescue	Exception => ex
			puts "Twitter API LIMIT exceeded #{ex}"			
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
			report = profile.reports[time_key]
			previous_time_key = profile.reports.keys.select{|k| k < time_key}.last
			previous_report = unless previous_time_key.blank?
				profile.reports[previous_time_key]
			end

			followers = (profile.profile["followers_count"] == 0) ? average_followers : profile.profile["followers_count"]

			report.acceleration = (report.mentions / followers.to_f) - phi
			total_acceleration += report.acceleration
			
			report.velocity = (previous_report.blank? ? 0 : previous_report.velocity) + report.acceleration
			total_velocity += report.velocity

			past_report = profile.reports[2.hour.ago.strftime("%Y%m%d%H")].
			report.previous_ranking = past_report.ranking unless  past_report.blank?

			accelerated_users[report.acceleration] ||= []
			accelerated_users[report.acceleration] << {:username => user, :report => report}

		end
		puts "saving"

		period_report = PeriodReport.find(time_query) || PeriodReport.new(:_id => time_query, :time => time_query)
		period_report.mentions = total_mentions
		period_report.average_followers =  average_followers
		period_report.average_acceleration = total_acceleration / users.length
		period_report.average_velocity = total_velocity / users.length
		period_report.sorted_users = accelerated_users.sort.reverse.map{|acceleration, a_users| a_users}.flatten
		period_report.save

		users.each do |user, info| 
			report = info.reports[time_key]
			accelerations = accelerated_users.keys.select{|a| a < report.acceleration}
			report.ranking = 1
			accelerations.each do |a|
				report.ranking += accelerated_users[a].length
			end
			info.save 
		end
	rescue Exception => ex
		HoptoadNotifier.notify ex
		raise ex				
	end
	end
end
