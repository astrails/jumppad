require 'open-uri'

# CONFIG

HOPTOAD_API_KEY = ""
RACK_BUG_PASSWORD = ""

raise "missing configuration" if [HOPTOAD_API_KEY, RACK_BUG_PASSWORD].any?(&:blank?)

##### HELPERS #####

NAME = File.basename(File.expand_path(root))

def braid_plugin repo
  run "braid add -p #{repo} | tee -a log/braid.log 2>&1"
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

run "rmdir tmp/{pids,sessions,sockets,cache}"
run "rm README log/*.log public/index.html public/images/rails.png public/favicon.ico"
run("find . \\( -type d -empty \\) -and \\( -not -regex ./\\.git.* \\) -exec touch {}/.gitignore \\;")
git :init

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

commit "basic files"

# RSPEC
gem 'rspec', :version => '1.2.6', :lib => false
gem 'rspec-rails', :version => '1.2.6', :lib => false
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

# HAML
gem 'haml', :version => '>= 2.0.9'

run "haml --rails ."

initializer "haml.rb", <<-RUBY
Haml::Template.options[:escape_html] = true
RUBY

commit 'haml'

# HOPTOAD
braid_plugin "git://github.com/thoughtbot/hoptoad_notifier.git"

initializer "hoptoad.rb", <<-RUBY
HoptoadNotifier.configure do |config|
  config.api_key = '#{HOPTOAD_API_KEY}'
  config.environment_filters << 'rack-bug.*'
end
RUBY

gsub_file "app/controllers/application_controller.rb", "end$", <<-RUBY
  include HoptoadNotifier::Catcher
end
RUBY

commit 'added hoptoad_notifier plugin'

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

commit "jquery validation"

# FORMTASTIC
gem "formtastic", :source => 'http://gemcutter.org/'
generate(:formtastic_stylesheets)
commit "formtastic stylesheets"

# GEMS
gem 'will_paginate', :source => 'http://gemcutter.org/'
gem 'whenever', :lib => false, :source => 'http://gemcutter.org/'
gem "inaction_mailer", :lib => 'inaction_mailer/force_load', :source => 'http://gemcutter.org', :env => 'development'
gem "ffmike-query_trace", :lib => 'query_trace', :source => 'http://gems.github.com', :env => 'development'

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

file "app/views/layouts/application.html.haml", <<-HAML
%html{ "xml:lang" => "en", :lang => "en", :xmlns => "http://www.w3.org/1999/xhtml" }
  %head
    %meta{ :content => "text/html; charset=utf-8", "http-equiv" => "Content-type" }
    %title!= @page_title || h(controller.action_name)
    != stylesheet_link_tag 'formtastic', 'formtastic_changes', 'application', :media => 'all'
    != javascript_include_tag "jquery.min.js", "jquery-ui.min.js", "jquery.validate.min.js", "application"
    != yield :head
  %body
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
environment "config.middleware.use 'Rack::Bug', :password => '#{RACK_BUG_PASSWORD}'"
commit "rack-bug"

# PLUGINS

braid_plugin "git://github.com/thoughtbot/factory_girl.git"
braid_plugin "git://github.com/relevance/log_buddy.git"
braid_plugin "git://github.com/josevalim/inherited_resources.git"
braid_plugin "git://github.com/thoughtbot/paperclip.git"
braid_plugin "git://github.com/ryanb/trusted-params.git"

braid_plugin "git://github.com/astrails/restart_controller.git"
braid_plugin "git://github.com/astrails/let_my_controller_go.git"

# AUTH
gem 'authlogic', :version => '2.1.1'
commit "authlogic"

braid_plugin "git://github.com/astrails/astrails-user-auth"
generate 'astrails_user_auth'
rake('db:migrate')
commit 'astrails_user_auth'







__END__



rakefile 'mail.rake', <<-END
namespace :mail do
  desc "Remove all files from tmp/sent_mails"
  task :clear do
    FileList["tmp/sent_mails/*"].each do |mail_file|
      File.delete(mail_file)
    end
  end
end
END
