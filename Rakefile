require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

desc 'Default: run specs.'
task :default => :spec
task :specs => :spec


# Derived from https://raw.githubusercontent.com/ruby-rdf/rdf/develop/Rakefile
require 'rdf/cli/vocab-loader'

desc "Generate Vocabularies"
vocab_sources = {
  vivo:  {
   uri: 'http://vivoweb.org/ontology/core#',
   source: 'http://vivoweb.org/files/vivo-isf-public-1.6.owl',
   strict: true
  },
  vivo_vcard:  {
   uri: 'http://www.w3.org/2006/vcard/ns#',
   source: 'lib/rdf/vocab/vivo_vcard.owl',
   strict: true
  }
}

task :gen_vocabs => vocab_sources.keys.map {|v| "lib/rdf/vocab/#{v}.rb"}

vocab_sources.each do |id, v|
  file "lib/rdf/vocab/#{id}.rb" => :do_build do
    puts "Generate lib/rdf/vocab/#{id}.rb"
    begin
      out = StringIO.new
      loader = RDF::VocabularyLoader.new(id.to_s.upcase)
      loader.uri = v[:uri]
      loader.source = v[:source] if v[:source]
      loader.extra = v[:extra] if v[:extra]
      loader.strict = v.fetch(:strict, true)
      loader.output = out
      loader.run
      out.rewind
      File.open("lib/rdf/vocab/#{id}.rb", "w") {|f| f.write out.read}
    rescue
      puts "Failed to load #{id}: #{$!.message}"
    end
  end
end

task :do_build
