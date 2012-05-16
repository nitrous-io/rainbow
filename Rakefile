desc 'run tests'
task :test, :file do |t, args|
  file = args.file || 'test/**/*_spec.*'
  system "node_modules/.bin/mocha #{file}"
end

task :default => [:test]

