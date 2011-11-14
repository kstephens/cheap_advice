require 'rubygems'
require 'bundler'
begin
  Bundler.setup(:default, :development)
rescue Bundler::BundlerError => e
  $stderr.puts e.message
  $stderr.puts "Run `bundle install` to install missing gems"
  exit e.status_code
end
require 'rake'

require 'jeweler'
Jeweler::Tasks.new do |gem|
  # gem is a Gem::Specification... see http://docs.rubygems.org/read/chapter/20 for more options
  gem.name = "cheap_advice"
  gem.homepage = "http://github.com/kstephens/cheap_advice"
  gem.license = "MIT"
  gem.summary = %Q{Add dynamic advice wrappers to methods.}
  gem.description = %Q{http://kurtstephens.com/pub/cheap_advice.slides/index.html}
  gem.email = "ks.github@kurtstephens.com"
  gem.authors = ["Kurt Stephens"]
  # Include your dependencies below. Runtime dependencies are required when using your gem,
  # and development dependencies are only needed for development (ie running rake tasks, tests, etc)
  #  gem.add_runtime_dependency 'jabber4r', '> 0.1'
  #  gem.add_development_dependency 'rspec', '> 1.2.3'
end
Jeweler::RubygemsDotOrgTasks.new

require 'rspec/core'
require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new(:spec) do |spec|
  spec.pattern = FileList['spec/**/*_spec.rb']
end

RSpec::Core::RakeTask.new(:rcov) do |spec|
  spec.pattern = 'spec/**/*_spec.rb'
  spec.rcov = true
end

task :example do
  Dir['example/ex*.rb'].sort.each do | ex |
    cpid = Process.fork do 
      load ex
    end
    Process.wait(cpid) or raise "#{ex} failed"
  end
end

task :default => :spec
task :default => :example

require 'rake/rdoctask'
Rake::RDocTask.new do |rdoc|
  version = File.exist?('VERSION') ? File.read('VERSION') : ""

  rdoc.rdoc_dir = 'rdoc'
  rdoc.title = "cheap_advice #{version}"
  rdoc.rdoc_files.include('README*')
  rdoc.rdoc_files.include('lib/**/*.rb')
end

$SCARLET = ENV['SCARLET'] ||= File.expand_path("../../scarlet/bin/scarlet", __FILE__)

slides_src  = 'cheap_advice.slides.textile'
slides_html = 'doc/cheap_advice.slides/index.html'
file slides_html => slides_src do
  slides_dir = File.dirname(slides_html)
  sh "mkdir -p #{slides_dir}"
  sh "#{$SCARLET} -f html -g #{slides_dir}"
  sh "#{$SCARLET} -f html #{slides_src} > #{slides_html}"
  sh "open #{slides_html}"
end

task :doc => slides_html

task :publish => :doc do
  sh "rsync -aruzv doc/cheap_advice.slides/ kscom:kurtstephens.com/pub/cheap_advice.slides/"
end

