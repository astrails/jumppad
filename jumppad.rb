require 'open-uri'
require 'ruby-debug'

# CONFIG

HOPTOAD_API_KEY = ""
RACK_BUG_PASSWORD = ""

raise "missing configuration" if [HOPTOAD_API_KEY, RACK_BUG_PASSWORD].any?(&:blank?)

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
gem 'mocha', :version => '0.9.8', :library => false
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

file "spec/support/macros.rb", <<-RUBY
ActiveSupport::TestCase.class_eval do

  def object
    @object || Factory.build(@factory)
  end

  def default_action(action)
    method = {
      :new     => :get,
      :create  => :post,
      :index   => :get,
      :show    => :get,
      :edit    => :get,
      :update  => :put,
      :destroy => :delete
    }[action]

    @params ||= {
      :new     => {},
      :create  => proc {
        raise "undefined @param" unless @param
        {@param => Factory.attributes_for(@factory).except(:skip_session_maintenance)}},
      :index   => {},
      :show    => proc {{:id => object.id}},
      :edit    => proc {{:id => object.id}},
      :update  => proc {{:id => object.id, @param => Factory.attributes_for(@factory)}},
      :destroy => proc {{:id => object.id}}
    }[action]
    @params = @params.call if @params.is_a?(Proc)

    send method, action, @params
  end

  def eval_request(action = nil)
    meth = "do_\#{action || @action}"
    if respond_to?(meth)
      send(meth)
    else
      default_action(action || @action)
    end
  end

  def self.describe_action(action, &block)
    describe(action) do
      before(:each) {@action = action}
      instance_eval(&block)
    end
  end

  def self.it_should_redirect_to(url = nil, &block)
    it "should redirect to \#{url}" do
      eval_request
      if block
        url = instance_eval(&block)
      end
      should redirect_to(url)
    end
  end

  def self.it_should_require_login
    it_should_redirect_to "/login"
  end

  def self.it_should_render_template(template)
    it "should render template \#{template}" do
      eval_request
      should render_template(template)
    end
  end

  def self.it_should_assign(var)
    it "should assign \#{var}" do
      eval_request
      assigns[var].should_not be_nil
    end
  end

  def self.it_should_assign(var)
    it "should assign \#{var}" do
      eval_request
      assigns[var].should_not be_nil
    end
  end

  def self.it_should_fail_to_find
    it "should throw ActiveRecord::RecordNotFound" do
      proc {eval_request}.should raise_error(ActiveRecord::RecordNotFound)
    end
  end

  def self.it_should_not_route(action)
    it "should not route \#{action}" do
      proc {eval_request(action)}.should raise_error(ActionController::RoutingError)
    end
  end
end
RUBY

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

gsub_file "app/controllers/application_controller.rb", "end$", <<-RUBY or die
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

file "config/initializers/live_validations.rb", <<-RUBY
LiveValidations.use :jquery_validations, :default_valid_message => "", :validate_on_blur => true
RUBY
commit "live validation"

# FORMTASTIC
gem "formtastic", :source => 'http://gemcutter.org'
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
gem "inaction_mailer", :lib => 'inaction_mailer/force_load', :source => 'http://gemcutter.org', :env => 'development'
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
gem 'will_paginate', :source => 'http://gemcutter.org'
gem 'whenever', :lib => false, :source => 'http://gemcutter.org'
gem "ffmike-query_trace", :lib => 'query_trace', :source => 'http://gems.github.com', :env => 'development'
gem "factory_girl", :source => 'http://gemcutter.org', :env => "test"

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
    .header
      - if logged_in?
        Hello
        != link_to h(current_user.name), edit_user_path(current_user)
        [
        != link_to "logout", user_session_path, :method => :delete
        ]
      - else
        != link_to "login", login_path
        != link_to "register", signup_path
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

braid_plugin "git://github.com/relevance/log_buddy.git"
braid_plugin "git://github.com/josevalim/inherited_resources.git"
braid_plugin "git://github.com/astrails/inherited_resources_pagination.git"
braid_plugin "git://github.com/thoughtbot/paperclip.git"
braid_plugin "git://github.com/astrails/trusted-params.git"

braid_plugin "git://github.com/astrails/restart_controller.git"
braid_plugin "git://github.com/astrails/let_my_controller_go.git"

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

