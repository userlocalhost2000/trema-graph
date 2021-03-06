require 'graph/graph-entry'
require 'mysql'
require 'time'

module Graph
	class Route
		UNKNOWN_ROUTE_ID = 0

		@@last_route_id = 1

		# 不完全な (see. doc/implementation.txt) 経路のリスト [Array of Route]
		@@unknown = []

		# 完全な (see. doc/implementation.txt) 経路のリスト [Array of Route]
		@@known = []

		attr_reader :entries

		def initialize *entries
			# 経路の ID
			@id = UNKNOWN_ROUTE_ID

			# 経路を構成するフローエントリ [Array of Entry]
			@entries = []

			entries.each do |each|
				if ! @entries.include? each then
					@entries << each
				end
			end
		end

		def set_entry entry
			if ! @entries.include? entry then
				@entries << entry
			end
		end

		def unset_entry entry
			@entries.delete entry
		end

		# 当該経路にエントリを結合 (前方から)
		def append_frontend_entry entry
			# エントリが既に経路に存在するかの確認
			if ! @entries.include? entry then
				@entries.unshift(entry)
			end
		end

		# 当該経路にエントリを結合 (後方から)
		def append_backend_entry entry
			if ! @entries.include? entry then
				@entries << entry
			end
		end

		# 当該経路に別の経路を結合する
		def do_append_route route
			@entries += route.entries
		end

		# 引数で指定したエントリが結合可能な場合、結合を行う
		# @return
		#		true  : 結合を行った
		#		false : 結合を行えなかった
		def may_append_entry target
			ret = nil

			if target.is_appendable? @entries.first then
				append_frontend_entry target
				ret = true
			elsif @entries.last.is_appendable? target then
				append_backend_entry target
				ret = true
			end

			check_termination

			return ret
		end

		def check_termination
			if @entries.first.is_from_host? && @entries.last.is_to_host? && is_continuous then
				if @@unknown.include? self then
					set_known
				end
			else
				if @@known.include? self then
					set_unknown
				end
			end
		end
	
		def set_known
			if ! @@known.include? self then
				@@last_route_id += 1

				@entries.each_with_index do |each, index|
					each.route_id = @@last_route_id
					each.route_index = index
				end
	
				@@known << self
				@@unknown.delete self
			end
		end
	
		# unknown 経路に設定
		def set_unknown
			if ! @@unknown.include? self then
				@id = UNKNOWN_ROUTE_ID
	
				@@unknown << self
				@@known.delete self
			end
		end

		# ######################### #
		# Here is the class methods #
		# ######################### #
		
		# create a new entry and set it into the unknown-list
		def self.create entry
			route = Graph::Route.new entry

			route.set_unknown
		end

		# unknown 経路に指定したエントリを結合させる
		# @return
		#		When the target entry can append to a route, this routine returns the route, or nil.
		def self.may_append_entry entry
			ret = nil

			@@unknown.each do |each|
				# 結合可能な場合、結合を行う
				if each.may_append_entry entry then
					ret = each
					break
				end
			end

			return ret
		end

		# unknown 経路同士の結合を可能であれば行う
		# @return
		def self.may_append_route
			@@unknown.each do |target|
				is_continue = false

				@@unknown.each do |another|
					if target != another then
						if target.entries.last.is_appendable? another.entries.first then
							target.do_append_route another
							target.check_termination

							@@unknown.delete(another)
							is_continue = true
						elsif another.entries.last.is_appendable? target.entries.first then
							another.do_append_route target
							another.check_termination

							@@unknown.delete(target)
							is_continue = true
						end
					end

					if is_continue then
						break
					end
				end

				if is_continue then
					retry
				end
			end
		end

		def self.remove_entry entry
			do_remove_entry! @@unknown, entry
			do_remove_entry! @@known, entry
		end

		def self.store_db
			@@known.each do |each|
				each.each { |x| x.store_db }
			end
		end

		def self.dump_unknown
			print "[Route.dump_unknown] ==== show unknown routes ====\n"
			@@unknown.each do |each|
				each.entries.each do |entry|
					print "(#{entry.match.in_port}:#{entry.dpid}:#{entry.get_output_portnum}), "
				end
				print "\n"
			end
			print "[Route.dump_unknown] =============================\n"
		end

		def self.dump_known
			print "[Route.dump_known] ===== show known routes =====\n"
			@@known.each do |each|
				each.entries.each do |entry|
					print "(#{entry.match.in_port}:#{entry.dpid}:#{entry.get_output_portnum}), "
				end
				print "\n"
			end
			print "[Route.dump_known] =============================\n"
		end

		private
		# @entries メンバの始端と終端が接続可能かどうかを判定
		def is_continuous
			first = @entries.first
			last = @entries.last 
			prev = first
	
			@entries.each do |each|
				if each == first || each == last
					next
				end
	
				if ! prev.is_appendable? each
					return false
				end
	
				prev = each
			end
	
			return true
		end

		def self.do_remove_entry! list, entry
			list.each do |each|
				if each.entries.include? entry then
					each.unset_entry entry

					# remove target route from the @@unknown or @@known
					list.delete each

					# make routes for each the left of entry the removed route had.
					each.entries.each do |entry|
						Route.create entry
					end
				end
			end
		end
	end
end
