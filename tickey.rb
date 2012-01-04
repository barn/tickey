#!/usr/bin/env ruby
#

require 'rubygems'
require 'readline'    # http://bogojoker.com/readline/
require 'trollop'
require 'pp'
require 'redmine_client'
require 'yaml'

configfile = "#{ENV['HOME']}/.tickey.conf"

config = ''

if File.exists?(configfile)
  config = YAML::load(File.open(configfile))
else
  puts "no config file at #{configfile}"
  exit 1
end

api_token       = config["api_token"]
redmine_url     = config["redmine_url"]
redmine_project = config["redmine_project"]

body = ''

def get_project( redmine_project )
  proj = RedmineClient::Project.find( redmine_project )
  unless proj
    puts "Unable to find the project of #{redmine_project}"
    exit 10
  end
  return proj
end

def redmine_login( redmine_url , api_token )
  RedmineClient::Base.configure do
    self.site = redmine_url
    self.user = api_token
  end
end

def get_project_list
  project_list = {}
  projects = RedmineClient::Project.find(:all)
  projects.each do |p|
    project_list[p.id] = p.identifier
  end
end

def read_body
  body = []
  prompt = 'Body: '
  while line = Readline.readline( prompt )
    break if line.downcase == 'exit' or 
                line.downcase == 'quit' or
                line.downcase == '.'

    body << line
    prompt = '`---> '
  end
  body.join( "\n" )
end

def die( string )
  puts string
  exit 20
end

# See http://trollop.rubyforge.org/
opts = Trollop::options do
  opt :subject, "Subject line for ticket", :short => 's', :type => :string
  opt :debug, "Be noisey"
  opt :apitoken, "API token to use for redmine", :short => 'a'
  opt :url, "URL to Redmine/Chili", :short => 'u'
end

# can pass a file to it, or stdin. Or we'll start asking.
if ARGV.length != 0
  if ARGV[0] == "-"
    die "Sorry, you need to specify a subject on the command line to use STDIN" \
      unless opts[:subject]
    body = $stdin.read
  elsif File.exists? ARGV[0]
    body = File.open( ARGV[0] ) { |f| f.read }
  else
    die "File #{ARGV[0]} doesn't exist"
  end
end

api_token = opts[:apitoken] if opts[:apitoken]
redmine_login( redmine_url, api_token )

project = get_project( redmine_project )

# before we do readline, deal cleanly with Ctrl-C action
if body.empty? or opts[:subject].empty? 
  stty_save = `stty -g`.chomp
  trap('INT') { system('stty', stty_save); exit }
end

# If we've got a subject, use it.
subject = opts[:subject]
subject ||= Readline.readline( 'Subject: ' , true )

if body.empty?
  body = read_body
end

if opts[:debug]
  puts project.id
  puts "Subject: #{subject}"
  puts "Body: #{body}"
end

# now post the issue!
issue = RedmineClient::Issue.new(
  :subject => subject,
  :project_id => project.id,
  :description => body
)

# Try and save it.
begin
  issue.save
rescue => e
  puts "Failed to save ticket because of #{e}"
  exit 10
end

puts "#{redmine_url}/issues/#{issue.id} created at #{issue.created_on}"

# pp issue
