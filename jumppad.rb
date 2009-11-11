require 'open-uri'

# CONFIG

HOPTOAD_API_KEY = "foo"


##### HELPERS #####

NAME = File.basename(File.expand_path(root))

def braid_plugin repo
  run "braid add -p #{repo}"
end

def commit(comment)
  git :add => "."
  git :commit => "-am '#{comment}'"
end


##### TEMPLATE #####

# remove temp dirs
run "rmdir tmp/{pids,sessions,sockets,cache}"
# remove junk
run "rm README log/*.log public/index.html public/images/rails.png public/favicon.ico"
# keep empty dirs
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

# database.yml
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
file 'public/javascripts/jquery.js', open('http://ajax.googleapis.com/ajax/libs/jquery/1.2/jquery.min.js').read
file 'public/javascripts/jquery.full.js', open('http://ajax.googleapis.com/ajax/libs/jquery/1.2/jquery.js').read
file 'public/javascripts/jquery-ui.js', open('http://ajax.googleapis.com/ajax/libs/jqueryui/1.5/jquery-ui.min.js').read
file 'public/javascripts/jquery-ui.full.js', open('http://ajax.googleapis.com/ajax/libs/jqueryui/1.5/jquery-ui.js').read
# file 'public/javascripts/jquery.form.js', open('http://jqueryjs.googlecode.com/svn/trunk/plugins/form/jquery.form.js').read

file "public/javascripts/application.js", <<-JS
$(function() {
  // ...
});
  JS

commit "jquery"

braid_plugin "git://github.com/aaronchi/jrails.git"
braid_plugin "git://github.com/rakuto/jrails_in_place_editing"

# WILL_PAGINATE
gem 'mislav-will_paginate', :lib => "will_paginate"
commit "will_paginate"

# WHENEVER
gem 'javan-whenever', :lib => false, :source => 'http://gems.github.com', :version => '0.3.7'
commit "whenever"

# AUTHLOGIC
gem 'authlogic', :version => '2.1.1'
commit "authlogic"

# DELAYED JOB
braid_plugin "git://github.com/collectiveidea/delayed_job.git"
generate "delayed_job"
commit "delayed_job"

# GLOBAL PREFERENCES
braid_plugin "git://github.com/astrails/global_preferences"
generate "global_preferences"
commit "global_preferences"

# VLADIFY
braid_plugin "git://github.com/astrails/vladify.git"
generate "vladify"
commit "vladify"

# PLUGINS

braid_plugin "git://github.com/brynary/rack-bug.git"
braid_plugin "git://github.com/thoughtbot/factory_girl.git"
braid_plugin "git://github.com/relevance/log_buddy.git"
braid_plugin "git://github.com/josevalim/inherited_resources.git"

braid_plugin "git://github.com/astrails/restart_controller"
braid_plugin "git://github.com/astrails/let_my_controller_go.git"







