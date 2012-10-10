set :application, "action-box-server"
set :repository,  "git@github.com:action-io/#{application}.git"

set :scm, :git
set :deploy_via, :remote_cache
set :branch, :master
set :user, 'action'
set :deploy_to, "/var/apps/#{application}"
set :use_sudo, false
set :git_enable_submodules, 1
set :port, 65100

set :default_environment, {
  'PATH' =>  "$HOME/.nvm/v0.8.9/bin:$PATH"
}

default_run_options[:pty] = true
default_run_options[:shell] = '/bin/bash --login'

task :production do
  set :host, "rainbow-apse1.action.io"
end

task :staging do
  set :host, "rainbow-apse1-staging.action.io"
end

role :web, host
role :app, host

# if you want to clean up old releases on each deploy uncomment this:
after "deploy:restart", "deploy:cleanup"

# if you're still using the script/reaper helper you will need
# these http://github.com/rails/irs_process_scripts

namespace :deploy do
  task :finalize_update, :except => { :no_release => true } do
    run "chmod -R g+w #{latest_release}" if fetch(:group_writable, true)
    run <<-CMD
      rm -rf #{latest_release}/log #{latest_release}/node_modules &&
      ln -s #{shared_path}/log #{latest_release}/log &&
      ln -s #{shared_path}/node_modules #{latest_release}/node_modules
    CMD
  end

  task :start, :roles => :app do
    run "cd #{latest_release} && export $(cat .env) && forever start boot.js"
  end

  task :stop, :roles => :app do
    run "cd #{latest_release} && export $(cat .env) && forever stop boot.js"
  end

  task :restart, :roles => :app do
    run "cd #{latest_release} && export $(cat .env) && forever stop boot.js && forever start boot.js"
  end

  task :npm, :roles => :app do
    run <<-CMD
      cd #{latest_release} &&
      npm install node-gyp &&
      npm install &&
      npm install ws --ws:native &&
      npm prune &&
      cp #{shared_path}/config/.env #{latest_release}/ &&
      cp #{shared_path}/config/database.coffee #{latest_release}/config/
    CMD
  end

  task :restart, :roles => :app, :except => { :no_release => true } do
    run "cd #{latest_release} && export $(cat .env) && forever stop boot.js && forever start boot.js"
  end
end

after 'deploy:finalize_update', 'deploy:npm'
