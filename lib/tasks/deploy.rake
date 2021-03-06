# A collection of rake tasks to deploy applications to heroku. At the basic level, all that needs to be called
# in most cases is
#
# foreman run rake deploy:staging
#
# The foreman gem is used to include .env ENV variables, but if you have those defined elsewhere it can be excluded.
# Before deploying define the STAGING_APP_NAME ENV variables, etc.
#
# These rake tasks will automatically detect schema changes and deploy correctly based on that. To override
# use the 'rake deploy:staging:migrations' or 'rake deploy:staging:preboot' rake task options.
class RakeHerokuDeployer
  def initialize app_env
    @app_env = app_env
    @app = ENV["#{app_env.to_s.upcase}_APP_NAME"]
    @start_time = Time.now.to_i
    # On deployer app, we must use '~/vendor/heroku-toolbelt/bin/heroku'
    @heroku_cli = ENV['HEROKU_EXECUTABLE'] || 'heroku'

    if @app.blank?
      puts "Please add #{app_env.to_s.upcase}_APP_NAME environment variable in order to deploy"
      exit(1)
    end
  end

  # Uses git to determine if there are any DB migrations to run
  def auto_deploy
    if schema_change_since_last_release?
      puts "::::::: Schema Change Detected, Disabling Preboot :::::::::"
      run_migrations
    else
      puts "::::::: No Schema Change, Preboot Enabled :::::::::"
      deploy
    end
  end

  def run_migrations
    #start_deploy;  turn_off_preboot; push; turn_app_off; migrate; restart; run_data_migrations; turn_app_on; tag; stop_deploy;
    start_deploy; turn_off_preboot; push; migrate; restart; run_data_migrations; tag; stop_deploy; turn_on_preboot;
  end

  def deploy
    # turn_on_preboot; push; restart; tag;
    start_deploy; turn_on_preboot; push; run_data_migrations; tag; stop_deploy;
    #start_deploy;  push; turn_app_off; run_data_migrations; turn_app_on; tag; stop_deploy;
  end

  def rollback
    turn_app_off; push_previous; restart; turn_app_on;
  end

private

  # 1) Fetch remote heroku branch we are deploying to
  # 2) Do a diff of our branch to the production one
  # 3) See if any migrations were added
  def schema_change_since_last_release?
    remote_name = "#{@app}-deployer"
    system("git remote add #{remote_name} git@heroku.com:#{@app}.git") # may already exist, don't error if so
    exit(1) unless system("git fetch #{remote_name}")
    diff = `git diff --name-only #{remote_name}/master`

    if diff.blank? # If we get back an empty diff we either have an error or don't want to deploy anyways
      puts 'No diff for deploying'
      exit(0) # No need to fail, just exit. Also means nightly builds are green :).
    end

    exit(1) unless system("git remote remove #{remote_name}")
    diff.include?("db/migrate/")
  end

  # Nice to see how long things run
  def print_current_time
    puts Time.now
  end

  def start_deploy
    return unless ENV["NEPTUNE_API_KEY"].present?
    puts 'Turning off the neptune API while deploy is happening...'
    puts 'curl -X GET "https://www.neptune.io/api/v1/maintenance/<api_key>/on'
    puts `curl -X GET 'https://www.neptune.io/api/v1/maintenance/#{ENV["NEPTUNE_API_KEY"]}/on'`
  end

  def stop_deploy
    return unless ENV["NEPTUNE_API_KEY"].present?
    puts 'Turning on the neptune API since deploy is finished...'
    puts 'curl -X GET "https://www.neptune.io/api/v1/maintenance/<api_key>/off'
    puts `curl -X GET 'https://www.neptune.io/api/v1/maintenance/#{ENV["NEPTUNE_API_KEY"]}/off'`
  end

  def turn_on_preboot
    puts 'Turning on preboot...'
    Bundler.with_clean_env { puts `#{@heroku_cli} features:enable -a #{@app} preboot` }
    print_current_time
  end

  def turn_off_preboot
    puts 'Turning off preboot...'
    Bundler.with_clean_env { puts `heroku features:disable -a #{@app} preboot` }
    print_current_time
  end

  def push
    current_branch = `git rev-parse --abbrev-ref HEAD`.chomp
    branch_to_branch = (current_branch.length > 0) ? "#{current_branch}:master" : ""
    puts 'Deploying site to Heroku ...'
    puts "git push git@heroku.com:#{@app}.git #{branch_to_branch}"
    puts `git push git@heroku.com:#{@app}.git #{branch_to_branch}`

    # Set the latest app version so that caching and other code know what version of code
    # is running. See Rails.cache.set_expanded_key method.
    latest_commit = `git rev-parse HEAD`.first(6)
    puts "#{@heroku_cli} config:set RAILS_APP_VERSION=#{latest_commit} -a #{@app}"
    Bundler.with_clean_env { puts `#{@heroku_cli} config:set RAILS_APP_VERSION=#{latest_commit} -a #{@app}` }

    print_current_time
  end

  def restart
    puts 'Restarting app servers ...'
    Bundler.with_clean_env { puts `#{@heroku_cli} restart --app #{@app}` }
    print_current_time
  end

  def tag
    return unless @app_env == :production

    release_name = "#{@app}_release-#{Time.now.utc.strftime("%Y%m%d%H%M%S")}"
    puts "Tagging release as '#{release_name}'"
    puts `git tag -a #{release_name} -m 'Tagged release'`
    puts `git push --tags git@heroku.com:#{@app}.git`
    print_current_time
  end

  def migrate
    puts 'Running database migrations ...'
    Bundler.with_clean_env { puts `#{@heroku_cli} run 'bundle exec rake db:migrate LOG_LEVEL=info' --app #{@app}` }
    print_current_time
  end

  def run_data_migrations
    run_custom_command_cleanly('rake data:migrate', true)
  end

  def run_custom_command_cleanly(command, detached = false, log_level = 'info')
    Bundler.with_clean_env { puts `#{@heroku_cli} run#{detached ? ':detached' : ''} '#{command} LOG_LEVEL=#{log_level}' --app #{@app}` }
    print_current_time
  end

  def turn_app_off
    puts 'Putting the app into maintenance mode ...'
    Bundler.with_clean_env { puts `#{@heroku_cli} maintenance:on --app #{@app}` }
    print_current_time
  end

  def turn_app_on
    puts 'Taking the app out of maintenance mode ...'
    Bundler.with_clean_env { puts `#{@heroku_cli} maintenance:off --app #{@app}` }
    print_current_time
  end

  def push_previous
    prefix = "#{@app}_release-"
    releases = `git tag`.split("\n").select { |t| t[0..prefix.length-1] == prefix }.sort
    current_release = releases.last
    previous_release = releases[-2] if releases.length >= 2
    if previous_release
      puts "Rolling back to '#{previous_release}' ..."

      puts "Checking out '#{previous_release}' in a new branch on local git repo ..."
      puts `git checkout #{previous_release}`
      puts `git checkout -b #{previous_release}`

      puts "Removing tagged version '#{previous_release}' (now transformed in branch) ..."
      puts `git tag -d #{previous_release}`
      puts `git push git@heroku.com:#{@app}.git :refs/tags/#{previous_release}`

      puts "Pushing '#{previous_release}' to Heroku master ..."
      puts `git push git@heroku.com:#{@app}.git +#{previous_release}:master --force`

      puts "Deleting rollbacked release '#{current_release}' ..."
      puts `git tag -d #{current_release}`
      puts `git push git@heroku.com:#{@app}.git :refs/tags/#{current_release}`

      puts "Retagging release '#{previous_release}' in case to repeat this process (other rollbacks)..."
      puts `git tag -a #{previous_release} -m 'Tagged release'`
      puts `git push --tags git@heroku.com:#{@app}.git`

      puts "Turning local repo checked out on master ..."
      puts `git checkout master`
      puts 'All done!'
    else
      puts "No release tags found - can't roll back!"
      puts releases
    end
  end
end

namespace :deploy do
  namespace :staging do
    task :migrations do
      deployer = RakeHerokuDeployer.new(:staging)
      deployer.run_migrations
    end

    task :rollback do
      deployer = RakeHerokuDeployer.new(:staging)
      deployer.rollback
    end

    task :preboot do
      deployer = RakeHerokuDeployer.new(:staging)
      deployer.deploy
    end
  end

  task :staging do
    deployer = RakeHerokuDeployer.new(:staging)
    deployer.auto_deploy
  end

  namespace :demo do
    task :migrations do
      deployer = RakeHerokuDeployer.new(:demo)
      deployer.run_migrations
    end

    task :rollback do
      deployer = RakeHerokuDeployer.new(:demo)
      deployer.rollback
    end

    task :preboot do
      deployer = RakeHerokuDeployer.new(:demo)
      deployer.deploy
    end
  end

  task :demo do
    deployer = RakeHerokuDeployer.new(:demo)
    deployer.auto_deploy
  end

  namespace :production do
    task :migrations do
      deployer = RakeHerokuDeployer.new(:production)
      deployer.run_migrations
    end

    task :rollback do
      deployer = RakeHerokuDeployer.new(:production)
      deployer.rollback
    end

    task :preboot do
      deployer = RakeHerokuDeployer.new(:production)
      deployer.deploy
    end
  end

  task :production do
    deployer = RakeHerokuDeployer.new(:production)
    deployer.auto_deploy
  end

  task :all do
    deployer = RakeHerokuDeployer.new(:staging)
    deployer2 = RakeHerokuDeployer.new(:demo)
    deployer3 = RakeHerokuDeployer.new(:production)
    deployer.auto_deploy
    deployer2.auto_deploy
    deployer3.auto_deploy
  end

  namespace :all do
    task :migrations do
      deployer = RakeHerokuDeployer.new(:staging)
      deployer2 = RakeHerokuDeployer.new(:demo)
      deployer3 = RakeHerokuDeployer.new(:production)
      deployer.run_migrations
      deployer2.run_migrations
      deployer3.run_migrations
    end

    task :preboot do
      deployer = RakeHerokuDeployer.new(:staging)
      deployer2 = RakeHerokuDeployer.new(:demo)
      deployer3 = RakeHerokuDeployer.new(:production)
      deployer.deploy
      deployer2.deploy
      deployer3.deploy
    end
  end

  # A Helper method to see what the output is
  task :detect_schema_change do
    deployer = RakeHerokuDeployer.new(:staging)
    puts deployer.schema_change_since_last_release?
  end
end
