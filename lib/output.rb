=begin
Copyright 2009 to 2013, Andrew Horton

This file is part of WhatWeb.

WhatWeb is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 2 of the License, or
at your option) any later version.

WhatWeb is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with WhatWeb.  If not, see <http://www.gnu.org/licenses/>.
=end

class Output
  # if no f, output to STDOUT, 
	# if f is a filename then open it, if f is a file use it	
	def initialize(f = STDOUT)
	  f = STDOUT if f == "-"
		@f = f if f.class == IO or f.class == File
		@f = File.open(f,"a") if f.class == String
		@f.sync = true # we want flushed output
	end

	def close
		@f.close unless @f.class == IO
	end

	# perform sort, uniq and join on each plugin result
	def suj(plugin_results)
		suj={}
		[:certainty, :version, :os, :string, :account, :model, :firmware, :module, :filepath].map do  |thissymbol|
			t=plugin_results.map {|x| x[thissymbol] unless x[thissymbol].class == Regexp }.flatten.compact.sort.uniq.join(",")
			suj[thissymbol] = t
		end
		suj[:certainty] = plugin_results.map {|x| x[:certainty] }.flatten.compact.sort.last.to_i # this is different, it's a number
		suj
	end

	# sort and uniq but no join. just for one plugin result
	def sortuniq(p)
		su = {}
		[:name, :certainty, :version, :os, :string, :account, :model, :firmware, :module, :filepath].map do |thissymbol|
			unless p[thissymbol].class == Regexp
				t = p[thissymbol]
				t = t.flatten.compact.sort.uniq if t.is_a?(Array)
				su[thissymbol] = t unless t.nil?
			end					
		end
		# certainty is different, it's a number
		su[:certainty] = p[:certainty].to_i
		su
	end
end
# JSON Output #
class OutputJSON < Output

	def flatten_elements!(obj)
		if obj.class == Hash
			obj.each_value {|x| 
				flatten_elements!(x)
			}
		end

		if obj.class == Array
			obj.flatten!
		end
	end

	def utf8_elements!(obj)
		if obj.class == Hash
			obj.each_value {|x| 
				utf8_elements!(x)
			}
		end

		if obj.class == Array
			obj.each {|x| 
				utf8_elements!(x)
			}
		end

		if obj.class == String
#			obj=obj.upcase!
#			obj=Iconv.iconv("UTF-8",@charset,obj).join
#pp @charset
#pp obj.encoding
# read this - http://blog.grayproductions.net/articles/ruby_19s_string
			# replace invalid UTF-8 chars
			# based on http://stackoverflow.com/a/8873922/388038
			if String.method_defined?(:encode)
			  obj.encode!('UTF-16', 'UTF-8', :invalid => :replace, :replace => '')
			  obj.encode!('UTF-8', 'UTF-16')
			end
            obj = obj.force_encoding('UTF-8')

	#	obj=obj.force_encoding("ASCII-8BIT")
#puts obj.encoding.name
#		obj.encode!("UTF-8",{:invalid=>:replace,:undef=>:replace})

		end
	end

	def out(target, status, results)
		# nice
		sendTime=nil
		foo= {:port=>$PORT,
			  :task_id=>"124",
			  :userId=>"12171",
			  :plugins=>{},
			  :status=>status, 
			  :url=>target, 
			  :tags=>"",   #not sure
			  :banner=>$BANNER,
			  :timestamp_received=>$START_TIME,
			  :timestamp_sent=>nil,
			  :vps_name=>"",
			  :vps_ip_external=>"",
			  :vps_ip_internal=>"",
			  :priLevel=>5} 
		results.each do |plugin_name,plugin_results|		
#			thisplugin = {:name=>plugin_name}
			thisplugin = {}
			unless plugin_results.empty?
				# important info in brief mode is version, type and ?
				# what's the highest probability for the match?

				certainty = plugin_results.map {|x| x[:certainty] unless x[:certainty].class==Regexp }.flatten.compact.sort.uniq.last

				version = plugin_results.map {|x| x[:version] unless x[:version].class==Regexp }.flatten.compact.sort.uniq
				os = plugin_results.map {|x| x[:os] unless x[:os].class==Regexp }.flatten.compact.sort.uniq
				string = plugin_results.map {|x| x[:string] unless x[:string].class==Regexp }.flatten.compact.sort.uniq
				accounts = plugin_results.map {|x| x[:account] unless x[:account].class==Regexp }.flatten.compact.sort.uniq
				model = plugin_results.map {|x| x[:model] unless x[:model].class==Regexp }.flatten.compact.sort.uniq
				firmware = plugin_results.map {|x| x[:firmware] unless x[:firmware].class==Regexp }.flatten.compact.sort.uniq
				modules = plugin_results.map {|x| x[:module] unless x[:module].class==Regexp }.flatten.compact.sort.uniq
				filepath = plugin_results.map {|x| x[:filepath] unless x[:filepath].class==Regexp }.flatten.compact.sort.uniq

				if !certainty.nil? and certainty != 100
					thisplugin[:certainty] = certainty
				end

				thisplugin[:version] = version unless version.empty?
				thisplugin[:os] = os unless os.empty?
				thisplugin[:string] = string unless string.empty?
				thisplugin[:account] = accounts unless accounts.empty?
				thisplugin[:model] = model unless model.empty?
				thisplugin[:firmware] = firmware unless firmware.empty?
				thisplugin[:module] = modules unless modules.empty?
				thisplugin[:filepath] = filepath unless filepath.empty?
#				foo[:plugins] << thisplugin
				foo[:plugins][plugin_name.to_sym] = thisplugin
			end
		end
		@charset=results.map {|n,r| r[0][:string] if n=="Charset" }.compact.first

		unless @charset.nil? or @charset == "Failed"
			utf8_elements!(foo) # convert foo to utf-8
			flatten_elements!(foo)			
		else
			# could not find encoding force UTF-8 anyway
			utf8_elements!(foo) 
		end
		foo[:timestamp_sent]=Time.new.to_i(13)
		$semaphore.synchronize do 
			foo
		end
	end
	#当没有重定向的时候执行他
	def write(res)
		@f.puts JSON::generate(res)
	end
end
#13位时间戳
class Time
  alias :to_ii to_i
  def to_i(i=10)
    if i > 10
      Integer(("%10.#{i-10}f" % self.to_f).delete '.')
    else
      self.to_ii
    end
  end

  def Time.att(i)
    if i.to_s.length > 10
      s = i.to_s
      s[10,0] = '.'
      at(s.to_f)
    end
  end
end
# a = Time.new
# a = a.to_i(13)                #生成13位unix时间戳
# puts a
# puts Time.att(a) 

