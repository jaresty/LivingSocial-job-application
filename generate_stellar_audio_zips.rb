#!/usr/bin/ruby
#

$KCODE = 'u'

require 'rubygems'
require 'markaby'
require 'find'
require 'htmlentities'
require 'cmdparse'
require 'uri'
require 'jcode'

$DEBUG = true



class LanguageObject
	attr_accessor :parent, :name, :filename
	def initialize(params)
		@name = params[:name]
		@filename = params[:filename]
	end
end

class LanguageGrouping < LanguageObject
	attr_reader :children
	def initialize(params)
		@children = []
		super(params)
	end
	def add(child)
		child.parent = self
		@children << child
	end
	def visit(visitor)
		@children.each { |child| child.visit(visitor) }
	end
end


class Chapter < LanguageGrouping
	def visit(visitor)
		visitor.visit_chapter(self)
		super(visitor)
	end
end

class LanguageFile < LanguageObject
	@@next_fid = 1
	attr_accessor :filename
	attr_reader :fid
	def initialize(params)
		@fid = @@next_fid
		@@next_fid += 1
		super(params)
	end
	def visit(visitor)
		visitor.visit_file(self)
	end
end

class ArrayVisitor
	def initialize
		@language_objects = [[Chapter.new(:name => 'topDir', :filename => 'topDir'), []]]
	end

	def visit_chapter(chapter)
		@language_objects << [chapter, []]
	end

	def visit_file(file)
		@language_objects[-1][1] << file
	end
end

class CopyVisitor < ArrayVisitor
	def process
		@language_objects.each do | chapter, files |
			puts "/bin/mkdir -p 'output/#{chapter.name}/files/'" if $DEBUG
			system("/bin/mkdir -p 'output/#{chapter.name}/files/'") unless files.empty?
			files.each do | file |
				puts %{/bin/cp "#{file.filename}" "output/#{chapter.name}/files/#{file.fid}.mp3"} if $DEBUG
				system(%{/bin/cp "#{file.filename}" "output/#{chapter.name}/files/#{file.fid}.mp3"})
			end
		end
	end
end

class ZIPVisitor < ArrayVisitor
	def process
		@language_objects.each do | chapter, files |
			curDir = Dir.pwd
			command = "cd '#{chapter.filename}';/usr/bin/zip '#{curDir}/output/#{chapter.name}/#{chapter.name}.zip' *.mp3 > /dev/null" 
		#<<  (files.collect { |file| file.filename }).join("' '") << "' > /dev/null"
			command2 = "cd 'output/#{chapter.name}';/usr/bin/zip -r '../#{chapter.name}.zip' * " <<  " > /dev/null"
			next if files.empty?
			system(command) 
			system(command2) if $individual
		end
	end
end

class IndividualHTMLVisitor < ArrayVisitor
	def initialize(title)
		@title = title
		super()
	end
	def output_html(chapter, files)
		mab = Markaby::Builder.new(:title => @title)
	  return mab.html do
			head do
				style :type => 'text/css' do
					<<-EOS
						    table {width: 75%;}
						      .onrow {background-color: silver}
						      .offrow {background-color: white}
						   td a {
							    display: block; 
							    width: 50%;
							    margin-left: auto;
							    margin-right: auto;
							    background-image: url(sound.gif);
							    background-repeat: no-repeat;
							    background-position: left;
							    padding-left: 25px;
							    }
					EOS
				end
				title { @title }
			end
			h1 { @title }
				h2(:style => "clear: left", :id => chapter.name) { HTMLEntities.encode_entities(chapter.name, :basic, :named) }
				a(:href => URI.escape(chapter.name + ".zip", Regexp.union(/\?/, URI::UNSAFE))) { "download all #{HTMLEntities.encode_entities(chapter.name, :basic, :named)} files" }
			       table do	
				       rowclasses = ["onrow", "offrow"]
				       files.each_with_index do | file, i |
					       tr do
							td(:class => rowclasses[(i % rowclasses.length)]) do 
								a(:href => "files/#{file.fid}.mp3") { HTMLEntities.encode_entities(file.name, :basic, :named) } 
							end
					       end
					end
			       end
			end
		end
	def process
		@language_objects.each do | chapter, files |
			next if files.empty?
			begin
			  f = File.open("output/#{chapter.name}/index.html", "w")
				f << output_html(chapter, files)
			ensure
			  f.close
		  end
			
		end
	end

end

class CombinedHTMLVisitor < ArrayVisitor
	def initialize(title)
		@title = title
		super()
	end
	def process
		mab = Markaby::Builder.new(:language_objects => @language_objects, :title => @title)
		File.open("output/index.html", "w") do | f |
			f << mab.html do
				head do
					style :type => 'text/css' do
						<<-EOS
							    table {width: 75%;}
							      .onrow {background-color: silver}
							      .offrow {background-color: white}
							   td a {
								    display: block; 
								    width: 50%;
								    margin-left: auto;
								    margin-right: auto;
								    background-image: url(sound.gif);
								    background-repeat: no-repeat;
								    background-position: left;
								    padding-left: 25px;
								    }
						EOS
					end
					title { @title }
				end
				h1 { @title }
				self << (@language_objects.collect { | chapter, files | next if files.empty?;capture { a(:style => "font-size: 9pt;display: block;margin-bottom: 10px;padding: 5px;float: left; border: thin solid black;", :href => "\##{chapter.name}") { chapter.name } } }).join('')
				@language_objects.each do | chapter, files |
					next if files.empty?
					h2(:style => "clear: left", :id => chapter.name) { HTMLEntities.encode_entities(chapter.name, :basic, :named) }
					a(:href => chapter.name + '/' + chapter.name + ".zip") { "download all #{HTMLEntities.encode_entities(chapter.name, :basic, :named)} files" }
				       table do	
					       rowclasses = ["onrow", "offrow"]
					       files.each_with_index do | file, i |
						       tr do
								td(:class => rowclasses[(i % rowclasses.length)]) do 
									a(:href => "#{chapter.name}/files/#{file.fid}.mp3" ) { HTMLEntities.encode_entities(file.name, :basic, :named) } 
								end
						       end
						end
				       end
				end
			end
		end
	end
end


def build_languageObject(path, languageObject)
	Dir.entries(path).each do | file |
		next unless (file =~ /^\..*/).nil?
		fullPath = "#{path}/#{file}"
		if FileTest.directory?(fullPath)
			newChapter = Chapter.new(:name => file, :filename => fullPath)
			languageObject.add(newChapter)
			build_languageObject(newChapter.filename, newChapter)
		else
			languageObject.add(LanguageFile.new(:name => file, :filename => fullPath))
		end
	end
end

cmd = CmdParse::CommandParser.new(true)
cmd.program_name = 'generate_audio_listings'
cmd.program_version = [0, 1, 1]
cmd.banner = $0 + ': a program to create zipped audio files and web sites for publishing directly to stellar'

process = CmdParse::Command.new('process', false)
process.options = CmdParse::OptionParserWrapper.new do | opt |
	opt.on('-d', '--dir DIRECTORY', 'The input directory - all mp3s should be in \'chapter\' directories just within this directory') { | dir | $inputDir = dir }
	opt.on('-n', '--name NAME', 'The name to use for the web site title') {|name| $name = name }
	opt.on('-i', '--individual', 'Create an individual output folder for each input folder') { $individual = true }
end
process.description = %q{Processes a series of directories as 'chapters' that contain mp3's.  Outputs a web site and zips everything together for publishing on stellar.}
process.short_desc = %q{creates a series of archives of mp3 files for upload to stellar.  created for uploading language audio files to the web}
process.set_execution_block do
	parent_languageObject = LanguageGrouping.new($name)

	build_languageObject($inputDir, parent_languageObject)

	htmlVisitor = IndividualHTMLVisitor.new($name) if $individual
	htmlVisitor = CombinedHTMLVisitor.new($name) if $indivdual.nil?
	copyVisitor = CopyVisitor.new
	zipVisitor = ZIPVisitor.new
	parent_languageObject.visit(htmlVisitor)
	parent_languageObject.visit(copyVisitor)
	parent_languageObject.visit(zipVisitor)
	copyVisitor.process
	htmlVisitor.process
	zipVisitor.process
end

cmd.add_command( process )
cmd.add_command( CmdParse::HelpCommand.new )
cmd.add_command( CmdParse::VersionCommand.new )
cmd.parse

