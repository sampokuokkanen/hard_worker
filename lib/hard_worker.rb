# frozen_string_literal: true

require_relative 'hard_worker/version'
require_relative 'hard_worker/worker'
require 'drb'
require 'yaml'
require 'singleton'
require 'dry-configurable'
require 'hard_worker/client'
require 'hard_worker/rails' if defined?(::Rails::Engine)

# HardWorker is a pure Ruby job backend.
# It has limited functionality, as it only accepts
# jobs as procs, but that might make it useful if you don't
# need anything as big as Redis.
# Saves jobs into a file as YAML as long as they're not procs
# and reloads them when started again.
class HardWorker
  extend Dry::Configurable
  include Singleton unless $TESTING
  URI = "druby://localhost:#{$TESTING ? Array.new(4) { rand(10) }.join : "8788"}"
  FILE_NAME = 'hard_worker_dump'
  @@queue = Queue.new

  setting :rails, true
  setting :rails_path, '.'
  setting :workers, 1
  setting :connect, true
  setting :environment, 'development'

  def start
    boot_app
    load_jobs
    @worker_list = []
    HardWorker.config.workers.times do |_i|
      @worker_list << Thread.new { Worker.new }
    end
    return unless HardWorker.config.connect

    DRb.start_service(URI, @@queue, verbose: true)
    puts banner_and_info
    DRb.thread.join
  end
  alias initialize start

  def boot_app
    return unless rails?

    ENV['RAILS_ENV'] ||= HardWorker.config.environment
    require File.expand_path("#{HardWorker.config.rails_path}/config/environment.rb")
    require 'rails/all'
    require 'hard_worker/rails'
  end

  def rails?
    HardWorker.config.rails
  end

  def load_jobs
    jobs = YAML.load(File.binread(FILE_NAME))
    jobs.each do |job|
      @@queue.push(job)
    end
    File.delete(HardWorker::FILE_NAME) if File.exist?(HardWorker::FILE_NAME)
  rescue StandardError
    # do nothing
  end

  def reload
    load_jobs
  end

  def stop_workers
    @worker_list.each do |worker|
      Thread.kill(worker)
    end
    class_array = []
    @@queue.size.times do |_i|
      next if (klass_or_proc = @@queue.pop).instance_of?(Proc)

      class_array << klass_or_proc
    end
    File.open(FILE_NAME, 'wb') { |f| f.write(YAML.dump(class_array)) }
  end

  def self.stop_workers
    @worker_list&.each do |worker|
      Thread.kill(worker)
    end
    class_array = []
    @@queue.size.times do |_i|
      next if (klass_or_proc = @@queue.pop).instance_of?(Proc)

      class_array << klass_or_proc
    end
    File.open(FILE_NAME, 'wb') { |f| f.write(YAML.dump(class_array)) }
  end

  # rubocop:disable Layout/LineLength
  # rubocop:disable Metrics/MethodLength
  def banner
    <<-'BANNER'
    .----------------. .----------------. .----------------. .----------------. .----------------. .----------------. .----------------. 
    | .--------------. | .--------------. | .--------------. | .--------------. | .--------------. | .--------------. | .--------------. |
    | |   ______     | | |  _________   | | |   _____      | | |      __      | | |  _________   | | |  _________   | | |  ________    | |
    | |  |_   _ \    | | | |_   ___  |  | | |  |_   _|     | | |     /  \     | | | |  _   _  |  | | | |_   ___  |  | | | |_   ___ `.  | |
    | |    | |_) |   | | |   | |_  \_|  | | |    | |       | | |    / /\ \    | | | |_/ | | \_|  | | |   | |_  \_|  | | |   | |   `. \ | |
    | |    |  __'.   | | |   |  _|  _   | | |    | |   _   | | |   / ____ \   | | |     | |      | | |   |  _|  _   | | |   | |    | | | |
    | |   _| |__) |  | | |  _| |___/ |  | | |   _| |__/ |  | | | _/ /    \ \_ | | |    _| |_     | | |  _| |___/ |  | | |  _| |___.' / | |
    | |  |_______/   | | | |_________|  | | |  |________|  | | ||____|  |____|| | |   |_____|    | | | |_________|  | | | |________.'  | |
    | |              | | |              | | |              | | |              | | |              | | |              | | |              | |
    | '--------------' | '--------------' | '--------------' | '--------------' | '--------------' | '--------------' | '--------------' |
     '----------------' '----------------' '----------------' '----------------' '----------------' '----------------' '----------------' 
    BANNER
  end

  def banner_and_info
    puts banner
    puts 'HardWorker is going to change to Belated!'
    puts "Currently running HardWorker version #{HardWorker::VERSION}"
    puts %(HardWorker running #{@worker_list&.length.to_i} workers on #{URI}...)
  end

  def stats
    {
      jobs: @@queue.size,
      workers: @worker_list&.length
    }
  end

  def self.clear_queue!
    @@queue.clear
  end

  def job_list
    @@queue
  end

  def self.fetch_job
    @@queue.pop
  end

  class Error < StandardError; end
end
