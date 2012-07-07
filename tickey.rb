#!/usr/bin/env ruby
#

require 'rubygems'
require 'readline'    # http://bogojoker.com/readline/
require 'trollop'
require 'pp'
require 'redmine_client'
require 'yaml'
require 'tempfile'
require 'benchmark'

configfile = "#{ENV['HOME']}/.tickey.conf"

config = ''

if File.exists?(configfile)
  config = YAML::load(File.open(configfile))
else
  puts "no config file at #{configfile}"
  exit 1
end

api_token        = config['api_token']
redmine_url      = config['redmine_url']
redmine_project  = config['redmine_project']
redmine_projects = config['redmine_projects']
cache_file       = config['cache_file']

body = ''

# Monkey patching!
# https://github.com/anibalcucco/basecamp-wrapper/issues/11
class Hash
  def collect!(&block)
    ret = []
    self.each {|key,val|
      if val.kind_of? Array
        val.collect!{|subval| block.call subval }
        ret = val
      end
    }
    return ret
  end
end



def get_project( redmine_project )
  proj = nil

  time = Benchmark.realtime do
    proj = RedmineClient::Project.find( redmine_project )
  end

  unless proj
    puts "Unable to find the project of #{redmine_project}"
    exit 10
  end

  puts "Time to find that project '#{redmine_project}' was #{ '%.2f' % time } seconds by the way."
  return proj
end

def redmine_login( redmine_url , api_token )
  RedmineClient::Base.configure do
    self.site   = redmine_url
    self.user   = api_token
    # self.format = :json
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
  opt :editor, "Fire up vim", :short => 'e'
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

project = nil

# before we do readline, deal cleanly with Ctrl-C action
if body.empty? or opts[:subject].empty? 
  stty_save = `stty -g`.chomp
  trap('INT') { system('stty', stty_save); exit }
end

# Readline completition from http://bogojoker.com/readline/
list = [ 'puppet', 'puppetlabs', 'puppetlabs-modules',
  '@james', '@zleslie', '@adrient', '@zach'
].sort

# Add in all the projects as #project for tab completion
list << redmine_projects.collect { |x| '#' + x }
list.flatten!


comp = proc { |s| list.grep( /^#{Regexp.escape(s)}/ ) }

Readline.completion_append_character = " "
Readline.completion_proc = comp

# If we've got a subject, use it.
subject = opts[:subject]
subject ||= Readline.readline( 'Subject: ' , true )

# Now we need to do something clever with the subject, to parse it for
# things. Only picks the first one it finds, which is kinda lame, but oh
# well.
redmine_projects.each do |proj|
  if subject =~ /\# #{proj} \b /ix
    begin
      project = get_project( proj )
      subject = $` + $' # so obvious, this is:
      # $` contains the string before the actual matched
      # string of the previous successful pattern match.
      # and then
      # $' contains the string after the actual matched string of the
      # previous successful pattern match.
    rescue => e
      puts "#{e} happened. bad."
      exit
    end
    break
  end
end

# Default to redmine_project.
if project.nil?
  project = get_project( redmine_project )
end


if body.empty?
  if opts[:editor]
    # vi tempfile...
    temp = Tempfile.new( 'tickeypoos', '/tmp/' )
    temp.close
    system( "${EDITOR:vi} #{temp.path}" )
    File.open( temp.path , 'r' ) do |f|
      body = f.readlines.join
    end
    temp.unlink
  else
    body = read_body
  end
end


if opts[:debug]
  puts "Project of #{project} with id of #{project.id}"
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

# Strip multiple //s but not the one in http://
issue_url = "#{redmine_url}/issues/#{issue.id}".gsub( /\/+/ , '/' ).sub( /^(https?:)\/\b/ , '\1//' )

puts "#{issue_url} created at #{issue.created_on}"

if RUBY_PLATFORM =~ /darwin/
  system( "echo '#{issue_url}' | pbcopy" )
end

# pp issue
