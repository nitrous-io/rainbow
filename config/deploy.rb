set :application, "action-box-server"
set :repository,  "git@github.com:petejkim/#{application}.git"

set :scm, :git
set :deploy_via, :remote_cache
set :branch, :master
set :user, 'action'
set :deploy_to, "/var/apps/#{application}"
set :use_sudo, false

default_run_options[:pty] = true

set :host, "dominus-usw-1.action.io"
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
    run "sudo start #{application}"
  end

  task :stop, :roles => :app do
    run "sudo stop #{application}"
  end

  task :restart, :roles => :app do
    start
  end

  task :npm, :roles => :app do
    run <<-CMD
      cd #{latest_release} &&
      npm install node-gyp &&
      npm install &&
      npm install ws --ws:native &&
      npm prune &&
      cp #{shared_path}/database.coffee #{latest_release}/config/
    CMD
  end

  task :restart, :roles => :app, :except => { :no_release => true } do
    run "if [ -f /var/run/action-box-server.pid ]; then sudo stop #{application}; fi"
    run "sudo start #{application}"
  end
end

after 'deploy:finalize_update', 'deploy:npm'