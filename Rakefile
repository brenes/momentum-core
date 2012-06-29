$KCODE = "u"
require 'rubygems'
require 'time'
require 'twitter/json_stream'
require './vendor/em-couchdb/lib/em-couchdb.rb'
require 'rake'
require "twitter"
require "couchrest"
require "couchrest_model"
require "hoptoad_notifier"
require "right_aws"

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
		    :auth    => "#{settings["twitter"]["username"]}:#{settings["twitter"]["password"]}",
		    :port           => 443,
      	:ssl            => true
		  )
		  couch = EventMachine::Protocols::CouchDB.connect :host => 'localhost', :port => 5984, :database => 'twitter-stream'
		  stream.each_item do |item|
			begin
				tweet = Tweet.from_hash JSON.parse(item)
				usernames = tweet.mentioned_users
				unless usernames.empty? 
					couch.save('tweets', tweet.to_json_object) do end
				end
			rescue Exception => ex
				puts "NO JSON: #{ex}"
				HoptoadNotifier.notify
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
					users[user].reports[time_key] = Hash.new 
					users[user].reports[time_key][:time] = time_key
					users[user].reports[time_key][:mentions] = 0
				end
				users[user].reports[time_key][:mentions] ||= 0
				users[user].reports[time_key][:mentions] += 1
			end
		end

		#we calculate aceleration, obtain the user, calculate velocity and store the info
				
		puts "sorting users"

		# Now we get a list of users sorted by the number of mentions
		top_users = {}
		users.each do |user, info|
			n_mentions = info.reports[time_key][:mentions]
			top_users[n_mentions] ||= []
			top_users[n_mentions] << user
		end

		puts "Getting Twitter Info"

		# Now we get the followers number for the most mentioned users
		api_requests = 0
		begin
			top_users.sort.reverse.each do |mentions, mentioned_users|
				mentioned_users.each do |user|
                               		unless users[user].profile.blank?
                                                puts "Not retrieving info for #{user}"
                                                followers += users[user].profile["followers_count"]
                                                users_with_followers += 1
					end
                                end
				mentioned_users.each do |user|
					begin
						if users[user].profile.blank?
							puts "Retrieving info for #{user}"
							twitter_profile = Twitter::Client.new.user(user.dup)
							users[user].profile = JSON.parse(twitter_profile.to_json)
							users[user].profile[:time] = time_query
							users[user].save
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

		if total_mentions == 0
			puts "No mentions"
			return;
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
			followers = (profile.profile.blank? or profile.profile["followers_count"] == 0) ? average_followers : profile.profile["followers_count"]

			report[:acceleration] = (report[:mentions] / followers.to_f) - phi
			total_acceleration += report[:acceleration]
			
			report[:velocity] = (previous_report.blank? ? 0 : previous_report[:velocity]||0) + (report[:acceleration] || 0)
			total_velocity += report[:velocity]

			past_report = profile.reports[2.hour.ago.strftime("%Y%m%d%H")].
			report[:previous_ranking] = past_report[:ranking] unless  past_report.blank?

			accelerated_users[report[:acceleration]] ||= []
			accelerated_users[report[:acceleration]] << {:username => user, :report => report}

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
			accelerations = accelerated_users.keys.select{|a| a > report[:acceleration]}
			report[:ranking] = 1
			accelerations.each do |a|
				report[:ranking] += accelerated_users[a].length
			end
			info.save 
		end
	rescue Exception => ex
		HoptoadNotifier.notify ex
		raise ex				
	end
	end

	desc "Saves tweets from the previous 30 days as a set of JSON files"
	task :archive do

		720.times do |i|
			lag = settings["archive"]["lag"]

			time_key = (lag+i).hour.ago.strftime("%Y %b %d %H") #"2011 Feb 01 19"

			puts "Getting tweets for #{time_key}"

			tweets =  Tweet.view "by_hour", :key => time_key

			puts "#{tweets.length} tweets"
			unless tweets.blank?
				puts "Archiving #{tweets.length} tweets (#{(lag+i).hour.ago.strftime("%Y%m%d%H")})"
				File.open("#{settings["archive"]["tweets_folder"]}/#{(lag+i).hour.ago.strftime("%Y%m%d%H")}", 'w') {|f| f.write(tweets.to_json) }	
				puts "Clearing tweets"
				tweets.each do |t| 
						t.destroy 
				end

			end
			puts "Done"
		end

			puts "Compacting database"
			EventMachine::run {
			  couch = EventMachine::Protocols::CouchDB.connect :host => 'localhost', :port => 5984, :database => 'twitter-stream'
			  couch.compact("tweets") do
			  	# Once we have compacted the database we can close the EventMachine loop
				EventMachine::stop_event_loop
			  end
			}

	end

	desc "Collects tweets and analyzes in realtime the mentions (experimental mode)"
	task :realtime do

		# This 'Realtime version' has an issue that must be debugged, but could be a first draft version
		#
		#   * If a user is mentioned at 9:30 and gets mentioned again at 9:50 we will use data from period (8:00 - 8:59) to calculate phi and thus the acceleration (That's cool)
		# 	* If it's get mentioned again at 10:10 we will use data from period (9:00-9:59) to calculate the whole phi even if 10 minutes (9:50-9:59) should get calculated using data from previous period (8:00-8:59)
		# 	* If it's get mentioned again at 12:30 we will use data from period (11:00-11:59) to calculate the whole phi but 50 minutes (10:10-10:59) shold get calculated with data from period (9:00-9:59) and a whole hour (11:00-11:59) with data from period (10:00-10:59)
		# This is important as not every hour in twitter has the same characteristics (sleep time, working time...)

	begin


		EventMachine::run {

		  stream = Twitter::JSONStream.connect(
		    :path    => "/1/statuses/filter.json?track=#{settings["twitter"]["track_word"]}",
		    :auth    => "#{settings["twitter"]["username"]}:#{settings["twitter"]["password"]}",
		    :port           => 443,
      	:ssl            => true
		  )

		  couch = EventMachine::Protocols::CouchDB.connect :host => 'localhost', :port => 5984, :database => 'twitter-realtime-stream'

			# On every tweet
		  stream.each_item do |item|
			begin
				tweet = Tweet.from_hash JSON.parse(item)
				usernames = tweet.mentioned_users
				unless usernames.empty?

					# We get the previous hourly report to get some variables such as the average number of mentions, followers, etc. and the current one so we fill it
					current_hour = tweet.created_at.strftime("%Y %b %d %H")
					previous_hour = (tweet.created_at - 1.hour).strftime("%Y %b %d %H")
					previous_period_report = PeriodReport.find(previous_hour)

					# Now, with twitter info we shoud be able to compute Phi. We need:
					# The average number of mentions per hour (for now, the mentions in this period)
					mentions_per_hour = previous_period_report.mentions
					# Number of users
					users_per_hour = previous_period_report.users
					average_mentions_per_hour = mentions_per_hour / users_per_hour
					# The average number of followers for a user (taken from the users mentioned in the last period)
					average_followers = previous_period_report.followers / previous_period_report.users_with_followers

					# Phi is a measure of how easy is to be replied.
					# If it's too easy (Phi too large because each user got a lot of mentions or had few followers when mentioned) you should have a lot of mentions or few followers to have any merit
					# If it's too hard (Phi too small because each user got few mentions or had a lot of followers to get the mentions) you could have merit even having less mentions or more followers
					phi = average_mentions_per_hour / average_followers

					puts "mentions: #{average_mentions}"
					puts "users: #{total_users}"
					puts "followers: #{average_followers}"
					puts "phi: #{phi}"

					# variables to store how must we update the current period
					followers = 0
					mentions = usernames.count
					new_mentioned_users = 0
					new_users_with_followers = 0

					usernames.each do |username|

						# We get or create the user
						user = User.find "u_#{username}"
						user ||= User.new :_id => "u_#{username}", :nickname => username

						# We get its follower number from twitter API if its info is too old

						begin
							if user.followers.blank?
								puts "Retrieving info for #{user.nickname}"
								twitter_profile = Twitter::Client.new.user(user.nickname)
								twitter_profile = JSON.parse(twitter_profile.to_json)
								user.followers = twitter_profile["followers_count"]
							end
						rescue Twitter::NotFound => ex
							puts "User not found: #{ex}"
						end

						first_mention =  user.last_mention_at.strftime("%Y %b %d %H") < current_hour

						# Now let's increment the period variables
						unless user.followers.nil?
							followers += user.followers
							new_mentioned_users += 1 if first_mention
						end

						new_users_with_followers += 1 if first_mention

						# We compute the new score for the user
						user_followers = user.followers
						hours_since_last_mention = (tweet.created_at - user.last_mention_at)/3600.0
						user.acceleration +=  1/(user_followers * hours_since_last_mention) - phi
						user.velocity += user.acceleration * hours_since_last_mention

						# And save it
						user.save

					end

					# We get the current report and save it
					current_period_report = PeriodReport.find(current_hour) || PeriodReport.new(:_id => time_query, :time => current_hour)
					current_period_report.mentions += mentions
					current_period_report.followers += followers
					current_period_report.users += new_mentioned_users
					current_period_report.users_with_followers += new_users_with_followers

					current_period_report.save
					tweet.save

				end
			rescue Exception => ex
				puts "NO JSON: #{ex}"
				HoptoadNotifier.notify
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
end
