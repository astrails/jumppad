#### START CONFIG ##########

NO_AUTH = false # skip the authlogic config part
HOPTOAD_API_KEY = ""
RACK_BUG_PASSWORD = ""

#### END CONFIGURATION #####

require 'open-uri'
require 'ruby-debug'

raise "missing rack-bug configuration" if RACK_BUG_PASSWORD.blank?

if HOPTOAD_API_KEY.blank?
	puts "WARNING: No HOPTOAD SUPPORT. Please set HOPTOAD_API_KEY"
	NO_HOPTOAD = true
else
	NO_HOPTOAD = false
end

##### HELPERS #####

NAME = File.basename(File.expand_path(root))

def die(message = caller.first)
  raise "\nERROR: #{message}\n"
end

def braid_plugin repo
  run("braid add -p #{repo} | tee -a log/braid.log 2>&1") or die("failed to braid #{repo}")
end

def commit(comment)
  git :add => "."
  git :commit => "-am '#{comment}'"
end

def download(url)
  open(url).read
end

def github_file(repo, path, version = "master")
  download("http://github.com/#{repo}/raw/#{version}/#{path}")
end

##### TEMPLATE #####

run "rmdir tmp/{pids,sessions,sockets,cache}" or die
run "rm README log/*.log public/index.html public/images/rails.png public/favicon.ico" or die
run("find . \\( -type d -empty \\) -and \\( -not -regex ./\\.git.* \\) -exec touch {}/.gitignore \\;") or die
git(:init)

file '.gitignore', <<-GITIGNORE
log/*.log
log/*.pid
db/*.db
db/*.sqlite3
tmp/**/*
.DS_Store
doc/api
doc/app
config/database.yml
autotest_result.html
coverage
public/javascripts/*_[0-9]*.js
public/stylesheets/*_[0-9]*.css
public/attachments
attic/
GITIGNORE

file "config/database.yml", <<-DB
defaults: &defaults
  adapter: mysql
  username: astrails
  password:
  encoding: utf8

production:
  database: #{NAME}
  <<: *defaults

development:
  database: #{NAME}
  <<: *defaults

test:
  database: #{NAME}_test
  <<: *defaults
DB

run "cp config/database.yml config/database.yml.sample"

commit "initial"
rake('db:create')

# BASIC FILES

file 'app/controllers/application_controller.rb', <<-RUBY
class ApplicationController < ActionController::Base
  helper :all
  protect_from_forgery
  filter_parameter_logging "password" unless Rails.env.development?
end
RUBY

file 'app/helpers/application_helper.rb', <<-RUBY
module ApplicationHelper
  def page_title(title=nil)
    if title.nil?
      @page_title ||= ""
    else
      @page_title = title
    end
  end

  def body_class
    "\#{controller.controller_name} \#{controller.controller_name}-\#{controller.action_name}"
  end
end
RUBY

file "config/routes.rb", <<-RUBY
ActionController::Routing::Routes.draw do |map|
end
RUBY

initializer 'requires.rb', <<-RUBY
Dir[Rails.root.join('lib', '*.rb')].each do |f|
  require f
end
RUBY

file "config/locales/en.yml", <<-YAML
en:
  flash:
    user_session:
      create:
        notice: "Logged in"
      destroy:
        notice: "Goodbye"
YAML

commit "basic files"

# RSPEC
gem 'rspec', :version => '1.3.0', :lib => false
gem 'rspec-rails', :version => '1.3.2', :lib => false
#gem 'mocha', :version => '0.9.8', :library => false
generate "rspec"

run "rm -rf test"

file "spec/spec.opts", <<-OPTS
--colour
--format specdoc
--format profile:log/spec-benchmark.log
--loadby mtime
--reverse
OPTS

commit "rspec"

file "lib/tasks/rcov.rake", <<-RUBY
require 'rcov/rcovtask'
Rcov::RcovTask.new do |t|
  t.test_files = FileList['test/test*.rb']
  # t.verbose = true     # uncomment to see the executed command
end
RUBY
commit "rcov.rake"

# HAML
gem 'haml', :version => '>= 3.0.12'

initializer "haml.rb", <<-RUBY
Haml::Template.options[:escape_html] = true
RUBY

commit 'haml'

#
unless NO_HOPTOAD
	# HOPTOAD
	braid_plugin "git://github.com/thoughtbot/hoptoad_notifier.git"

	initializer "hoptoad.rb", <<-RUBY
HoptoadNotifier.configure do |config|
	config.api_key = '#{HOPTOAD_API_KEY}'
	config.environment_filters << 'rack-bug.*'
end
	RUBY

	gsub_file "app/controllers/application_controller.rb", "end$", <<-RUBY or die
	include HoptoadNotifier::Catcher
end
	RUBY

	commit 'added hoptoad_notifier plugin'
end

# JQUERY & JRAILS
run "rm -f public/javascripts/*"
file 'public/javascripts/jquery.min.js',    download('http://ajax.googleapis.com/ajax/libs/jquery/1.3.2/jquery.min.js')
file 'public/javascripts/jquery.js',        download('http://ajax.googleapis.com/ajax/libs/jquery/1.3.2/jquery.js')
file 'public/javascripts/jquery-ui.min.js', download('http://ajax.googleapis.com/ajax/libs/jqueryui/1.7.2/jquery-ui.min.js')
file 'public/javascripts/jquery-ui.js',     download('http://ajax.googleapis.com/ajax/libs/jqueryui/1.7.2/jquery-ui.js')
file "public/javascripts/jquery.validate.min.js", github_file("ffmike/jquery-validate", "jquery.validate.min.js")

file "public/javascripts/application.js", <<-JS
$(function() {
  // ...
});
  JS

commit "jquery"

braid_plugin "git://github.com/aaronchi/jrails.git"
braid_plugin "git://github.com/rakuto/jrails_in_place_editing"

braid_plugin "git://github.com/augustl/live-validations.git"
braid_plugin "git://github.com/redinger/validation_reflection.git"

file "config/initializers/live_validations.rb", <<-RUBY
LiveValidations.use :jquery_validations, :default_valid_message => "", :validate_on_blur => true
RUBY
commit "live validation"

# FORMTASTIC
gem "formtastic"
generate :formtastic
File.open("config/initializers/formtastic.rb", "a") do |file|
  file.write <<-RUBY
Formtastic::SemanticFormBuilder.i18n_lookups_by_default = true
  RUBY
end
commit "formtastic"

# Time freezing it tests
gem 'timecop', :env => 'test'

# MAIL handling in development
gem "inaction_mailer", :lib => 'inaction_mailer/force_load', :env => 'development'
rakefile 'mail.rake', <<-RAKE
namespace :mail do
  desc "Remove all files from tmp/sent_mails"
  task :clear do
    FileList["tmp/sent_mails/*"].each do |mail_file|
      File.delete(mail_file)
    end
  end
end
RAKE

# GEMS
gem 'will_paginate'
gem 'whenever', :lib => false
gem "query_trace", :lib => 'query_trace', :env => 'development'
gem "factory_girl", :env => "test"

commit "gems"

# DELAYED JOB
braid_plugin "git://github.com/collectiveidea/delayed_job.git"
generate "delayed_job"
rake('db:migrate')
commit "delayed_job"

# GLOBAL PREFERENCES
braid_plugin "git://github.com/astrails/global_preferences"
generate "global_preferences"
rake('db:migrate')
file "config/initializers/mail.rb", <<-RUBY
domain = (GlobalPreference.get(:domain) || "#{NAME}.com") rescue "#{NAME}.com"
ActionMailer::Base.smtp_settings = {
  :address => "localhost",
  :port => 25,
  :domain => domain,
}
RUBY
commit "global_preferences"

# VLADIFY
braid_plugin "git://github.com/astrails/vladify.git"
generate "vladify"
commit "vladify"

# STATIC PAGES
braid_plugin "git://github.com/thoughtbot/high_voltage.git"
file "app/controllers/pages_controller.rb", <<-RUBY
class PagesController < HighVoltage::PagesController
end
RUBY
route "map.resources :pages, :controller => 'pages', :only => [:show]"
commit "static pages"

# LAYOUT

file "app/views/layouts/_flashes.html.haml", <<-HAML
#flash
  - flash.each do |key, value|
    %div{:id => "flash_\#{key}", :class => key}= value
HAML

unless NO_AUTH
  login_header = <<-HAML
      - if logged_in?
        Hello
        != link_to h(current_user.name), edit_user_path(current_user)
        [
        != link_to "logout", user_session_path, :method => :delete
        ]
      - else
        != link_to "login", login_path
        != link_to "register", signup_path
HAML
else
  login_header = nil
end

file "app/views/layouts/application.html.haml", <<-HAML
%html{ "xml:lang" => "en", :lang => "en", :xmlns => "http://www.w3.org/1999/xhtml" }
  %head
    %meta{ :content => "text/html; charset=utf-8", "http-equiv" => "Content-type" }
    %title!= @page_title || h(controller.action_name)
    != stylesheet_link_tag 'formtastic', 'formtastic_changes', 'application', :media => 'all'
    != javascript_include_tag "jquery.min.js", "jquery-ui.min.js", "jquery.validate.min.js", "application"
    != yield :head
  %body
    .header
#{login_header}
    .container
      != render :partial => 'layouts/flashes'
      != yield
HAML

file "public/stylesheets/application.css", <<-CSS
CSS

# mkdir "app/views/pages"
file "app/views/pages/home.html.haml", <<-HAML
Hello World
HAML
route "map.root :controller => :pages, :action => :show, :id => :home"

commit "layout"

# RACK BUG
braid_plugin "git://github.com/brynary/rack-bug.git"
# template adds lines in reversed order so we first use then define rpass
environment "config.middleware.use 'Rack::Bug', :password => rpass"
environment "rpass = (GlobalPreference.get(:rack_bug_password) || '#{RACK_BUG_PASSWORD}') rescue '#{RACK_BUG_PASSWORD}'"
commit "rack-bug"

# DEBUG
gem "ruby-debug", :library => false
environment "require 'ruby-debug'", :env => :development
environment "require 'ruby-debug'", :env => :test
commit "ruby-debug"

# PLUGINS

gem 'has_scope'
gem 'inherited_resources', :version => '1.0.0'
gem 'responders', :version => '0.4'
commit 'inherited_resources'

braid_plugin "git://github.com/relevance/log_buddy.git"
braid_plugin "git://github.com/astrails/inherited_resources_pagination.git"
braid_plugin "git://github.com/thoughtbot/paperclip.git"
braid_plugin "git://github.com/astrails/trusted-params.git"

braid_plugin "git://github.com/astrails/restart_controller.git"
braid_plugin "git://github.com/astrails/let_my_controller_go.git"


unless NO_AUTH
  # AUTH
  gem 'authlogic', :version => '2.1.1'

  gsub_file "spec/spec_helper.rb", "require 'spec/rails'", <<-RUBY
require 'spec/rails'
require 'authlogic/test_case'
  RUBY
  commit "authlogic"

  braid_plugin "git://github.com/astrails/astrails-user-auth"
  generate 'astrails_user_auth'
  rake('db:migrate')
  commit 'astrails_user_auth'
end
