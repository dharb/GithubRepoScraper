# To run script, navigate to GithubRepoScraper folder in your terminal and type the following line:
# env repo="repo/address" username="username" password="password" ruby scrape.rb
# where repo/address would be dharb/GithubRepoScraper for your repo here: https://github.com/dharb/GithubRepoScraper
# and username and password are your github username and password (they are passed directly to the github API using the octokit gem)
# This script currently outputs associated users with email addresses to files located in data folder
# Works well with large repositories, works with the API rate limit to run until all data has been fetched (large open source repos may take a really long time!)

#TODO: add two factor auth support


# load necessary gems
def load_gem(name, version=nil)
# needed if your ruby version is less than 1.9
# require 'rubygems'

  begin
    gem name, version
  rescue LoadError
    version = "--version '#{version}'" unless version.nil?
    system("gem install #{name} #{version}")
    Gem.clear_paths
    retry
  end
  require name
end
load_gem 'octokit'
load_gem 'json'
load_gem 'builder'

# Store responses in cache and serve them back up for future 304 responses for same resource
load_gem 'faraday-http-cache'
stack = Faraday::RackBuilder.new do |builder|
  builder.use Faraday::HttpCache
  builder.use Octokit::Response::RaiseError
  builder.adapter Faraday.default_adapter
end
Octokit.middleware = stack


Octokit.auto_paginate = true

# Beginning of actual script

class GithubUser
  attr_accessor :handle, :email, :name, :action, :associated_emails, :location, :company, :bio, :github_id
  def initialize(handle,email,name,action,associated_emails,location,company,bio,github_id)
    self.handle,self.email,self.name,self.action,self.associated_emails,self.location,self.company,self.bio,self.github_id = handle,email,name,action,associated_emails,location,company,bio,github_id
  end
end

# fetch user's public event history
def check_events(client,login)
  begin
    events = client.user_public_events login
  rescue Octokit::TooManyRequests => e
    puts "Hit rate limit, waiting #{client.rate_limit.resets_in / 60} minutes for reset..."
    sleep client.rate_limit.resets_in
    client = Octokit::Client.new login: ENV['username'], password: ENV['password']
    retry
  end
  authors = []
  events.each do |e|
    if e.type == "PushEvent"
      e.payload.commits.each do |com|
        authors << [com.author.name,com.author.email]
      end
    end
  end
  # return list of unique email/name combinations
  authors.uniq
end
# Initialize new xml document
file = File.new("data/#{ENV['repo'].split('/').last}.xml", "wb")
xml = Builder::XmlMarkup.new :target => file
# Keep track of how many API requests were used (github limits to 5000/hr)
used = 0
# Initialize empty list of users associated with repository
associated_users = []
# Authenticate with github. Rate limiting is by IP, so changing login info will not get you more requests
begin
  client = Octokit::Client.new login: ENV['username'], password: ENV['password']
rescue Octokit::TooManyRequests => e
  puts "Hit rate limit, waiting #{client.rate_limit.resets_in / 60} minutes for reset..."
  sleep client.rate_limit.resets_in
  retry
end
used += 1

# fetch users who have contributed to repository
puts "fetching contributors.."
begin
  contributors = client.contributors ENV['repo']
rescue Octokit::TooManyRequests => e
  puts "Hit rate limit, waiting #{client.rate_limit.resets_in / 60} minutes for reset..."
  sleep client.rate_limit.resets_in
  client = Octokit::Client.new login: ENV['username'], password: ENV['password']
  retry
end
used += 1
contrib_size = contributors.size
puts "TOTAL # CONTRIBUTORS: #{contrib_size}"
contributors.each_with_index do |c,i|
  associated_emails = ""
  begin
    user = client.user c.login
  rescue Octokit::TooManyRequests => e
    puts "Hit rate limit, waiting #{client.rate_limit.resets_in / 60} minutes for reset..."
    sleep client.rate_limit.resets_in
    client = Octokit::Client.new login: ENV['username'], password: ENV['password']
    retry
  end
  used += 1
  sleep 0.2
  login = user.login
  email = user.email
  name = user.name
  location = user.location
  company = user.company
  bio = user.bio
  github_id = user.id
  puts "#{login}   #{i+1}/#{contrib_size}"
  if email.nil?
    # Fetch user's public commits to check for associated email addresses
    commit_authors = check_events(client,login)
    commit_authors.each do |a|
      # If commit author name matches user name, scoop email address
      if !name.nil? && (a[0] == name || a[0].downcase == name.downcase)
        email = a[1]
      else
        associated_emails += "name: " + a[0] + ", email: " + a[1] + ";"
      end
    end
    used += 1
  end
  if !email.nil?
    gh_user = GithubUser.new(login, email, name, "contributed", associated_emails, location, company, bio, github_id)
    associated_users << gh_user
  end
end

# fetch users who are either watching or have starred repository
puts "fetching watched / starred.."
begin
  stargazers = client.stargazers ENV['repo']
rescue Octokit::TooManyRequests => e
  puts "Hit rate limit, waiting #{client.rate_limit.resets_in / 60} minutes for reset..."
  sleep client.rate_limit.resets_in
  client = Octokit::Client.new login: ENV['username'], password: ENV['password']
  retry
end
used += 1
star_size = stargazers.size
puts "TOTAL # WATCHED/STARRED: #{star_size}"
stargazers.each_with_index do |s,i|
  associated_emails = ""
  begin
    user = client.user s.login
  rescue Octokit::TooManyRequests => e
    puts "Hit rate limit, waiting #{client.rate_limit.resets_in / 60} minutes for reset..."
    sleep client.rate_limit.resets_in
    client = Octokit::Client.new login: ENV['username'], password: ENV['password']
    retry
  end
  used += 1
  sleep 0.2
  login = user.login
  email = user.email
  name = user.name
  location = user.location
  company = user.company
  bio = user.bio
  github_id = user.id
  puts "#{login}   #{i+1}/#{star_size}"
  if email.nil?
    commit_authors = check_events(client,login)
    commit_authors.each do |a|
      # If commit author name matches user name, scoop email address
      if !name.nil? && (a[0] == name || a[0].downcase == name.downcase)
        email = a[1]
      else
        associated_emails += "name: " + a[0] + ", email: " + a[1] + ";"
      end
    end
    used += 1
  end
  if !email.nil?
    gh_user = GithubUser.new(login, email, user.name, "starred/watched", associated_emails, location, company, bio, github_id)
    if associated_users.any?{|item| item.email == gh_user.email}
      repeated_user = associated_users[associated_users.find_index{|item| item.email == gh_user.email}]
      repeated_user.action = repeated_user.action + "; " + gh_user.action
    else
      associated_users << gh_user
    end
  end
end

# fetch users who have forked repository
puts "fetching forked.."
begin
  forks = client.forks ENV['repo']
rescue Octokit::TooManyRequests => e
  puts "Hit rate limit, waiting #{client.rate_limit.resets_in / 60} minutes for reset..."
  sleep client.rate_limit.resets_in
  client = Octokit::Client.new login: ENV['username'], password: ENV['password']
  retry
end
used += 1
fork_size = forks.size
puts "TOTAL # FORKED: #{fork_size}"
forks.each_with_index do |f,i|
  associated_emails = ""
  begin
    user = client.user f.owner['login']
  rescue Octokit::TooManyRequests => e
    puts "Hit rate limit, waiting #{client.rate_limit.resets_in / 60} minutes for reset..."
    sleep client.rate_limit.resets_in
    client = Octokit::Client.new login: ENV['username'], password: ENV['password']
    retry
  end
  used += 1
  sleep 0.2
  login = user.login
  email = user.email
  name = user.name
  location = user.location
  company = user.company
  bio = user.bio
  github_id = user.id
  puts "#{login}   #{i+1}/#{fork_size}"
  if email.nil?
    commit_authors = check_events(client,user.login)
    commit_authors.each do |a|
      # If commit author name matches user name, scoop email address
      if !name.nil? && (a[0] == name || a[0].downcase == name.downcase)
        email = a[1]
      else
        associated_emails += " name: " + a[0] + ", email: " + a[1] + "; "
      end
    end
  end
  if !email.nil?
    gh_user = GithubUser.new(login, email, user.name, "forked", associated_emails, location, company, bio, github_id)
    if associated_users.any?{|item| item.email == gh_user.email}
      repeated_user = associated_users[associated_users.find_index{|item| item.email == gh_user.email}]
      repeated_user.action = repeated_user.action + "; " + gh_user.action
    else
      associated_users << gh_user
    end
  end
end
puts "Total API calls used: " + used.to_s
# Output array to xml
xml.users{ associated_users.map{|x| xml.user { |u| u.name(x.name); u.login(x.handle); u.email(x.email); u.action(x.action); u.associated_emails(x.associated_emails); u.location(x.location); u.company(x.company); u.bio(x.bio); u.github_id(x.github_id)}}}
file.close
puts "Success!"
