#!/usr/bin/env ruby
# Usage: ruby gen_erigon_services.rb /path/to/erigon.service

require 'json'
require 'net/http'
require 'uri'
require 'fileutils'

# ---------------------------------------------------------------------------
# Ports that need to be unique per instance.
# Maps the flag name (as it appears in ExecStart) to an offset applied on top
# of the base instance offset.  The base offset per instance is 1, 2, 3 so
# instance N gets port + N for every tracked flag.
# ---------------------------------------------------------------------------
OFFSET_FLAGS = %w[
  --port
  --http.port
  --ws.port
  --authrpc.port
  --torrent.port
  --private.api.addr
  --beacon.api.port
  --metrics.port
].freeze

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def fetch_enode(rpc_url = 'http://localhost:8545')
  uri = URI(rpc_url)
  payload = JSON.generate(jsonrpc: '2.0', method: 'admin_nodeInfo', params: [], id: 1)

  http = Net::HTTP.new(uri.host, uri.port)
  http.open_timeout = 5
  http.read_timeout = 10

  request = Net::HTTP::Post.new(uri.path.empty? ? '/' : uri.path)
  request['Content-Type'] = 'application/json'
  request.body = payload

  response = http.request(request)
  data = JSON.parse(response.body)

  enode = data.dig('result', 'enode')
  raise "admin_nodeInfo returned no enode field.\nFull response: #{data.inspect}" unless enode

  # Replace 0.0.0.0 with 127.0.0.1 so secondary nodes can actually connect
  enode.gsub('0.0.0.0', '127.0.0.1')
rescue Errno::ECONNREFUSED => e
  abort "ERROR: Could not connect to Erigon RPC at #{rpc_url}\n  #{e.message}"
rescue JSON::ParserError => e
  abort "ERROR: Invalid JSON from RPC endpoint\n  #{e.message}"
end

# Increment only the numeric portion at the end of a value like "9091" or
# "127.0.0.1:9091".  Returns the bumped string.
def bump_port(value, delta)
  # addr:port  e.g. 127.0.0.1:9091
  if value =~ /\A(.*):(\d+)\z/
    "#{$1}:#{$2.to_i + delta}"
  # bare port  e.g. 30903
  elsif value =~ /\A(\d+)\z/
    ($1.to_i + delta).to_s
  else
    value
  end
end

# Parse ExecStart lines (handles trailing backslash continuations).
# Returns the raw multi-line ExecStart block as an array of lines (preserving
# indentation and backslashes) plus a flat list of [flag, value] pairs found.
def parse_exec_start(lines)
  in_exec = false
  exec_lines = []

  lines.each do |line|
    if line =~ /\AExecStart=/
      in_exec = true
      exec_lines << line
    elsif in_exec
      exec_lines << line
      break unless line.rstrip.end_with?('\\')
    end
  end

  exec_lines
end

# Rewrite the ExecStart block inside a full service file for a given instance.
def rewrite_service(content, instance_num, enode, datadir_base)
  delta = instance_num  # instance 2 => delta 1, instance 3 => delta 2, etc.
                        # (we pass 1-based offset directly)

  lines = content.lines
  result = []
  in_exec = false

  lines.each do |line|
    if line =~ /\AExecStart=/
      in_exec = true
    end

    unless in_exec
      # Rewrite Description line
      if line =~ /\ADescription=/
        result << line.sub(/\(.*?\)/, "(Secondary #{instance_num})")
        next
      end
      result << line
      next
    end

    # ---- We are inside ExecStart ----
    modified = line.dup

    # 1. Bump any recognised port flags  (--flag=VALUE  or  --flag VALUE)
    OFFSET_FLAGS.each do |flag|
      # --flag=value
      modified.gsub!(/#{Regexp.escape(flag)}=(\S+)/) do
        "#{flag}=#{bump_port($1, delta)}"
      end
      # --flag value  (flag followed by space then a value on same token)
      modified.gsub!(/#{Regexp.escape(flag)}\s+(\S+)/) do
        "#{flag} #{bump_port($1, delta)}"
      end
    end

    # 2. Rewrite --datadir
    modified.gsub!(/--datadir=(\S+)/) { "--datadir=#{$1}_secondary#{instance_num}" }
    modified.gsub!(/--datadir\s+(\S+)/) { "--datadir #{$1}_secondary#{instance_num}" }

    result << modified

    # After the last ExecStart line (no trailing backslash) inject our extra flags
    unless line.rstrip.end_with?('\\')
      # Strip the newline from the previous last line and re-add backslash
      if result.last =~ /\n\z/
        result[-1] = result[-1].chomp + " \\\n"
      end
      result << "  --nodiscover \\\n"
      result << "  --maxpeers=1 \\\n"
      result << "  --staticpeers=\"#{enode}\"\n"
      in_exec = false
    end
  end

  result.join
end

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

abort "Usage: #{$0} /path/to/erigon.service" if ARGV.empty?

service_path = ARGV[0]
abort "ERROR: File not found: #{service_path}" unless File.exist?(service_path)

puts "==> Fetching enode from http://localhost:8545 ..."
enode = fetch_enode
puts "    enode: #{enode}"

original_content = File.read(service_path)
base_name = File.basename(service_path, '.service')
output_dir = File.dirname(service_path)

(1..3).each do |i|
  instance_num = i + 1  # instances 2, 3, 4
  out_filename = "#{base_name}-secondary#{instance_num}.service"
  out_path     = File.join(output_dir, out_filename)

  new_content = rewrite_service(original_content, i, enode, '/var/lib/erigon')

  File.write(out_path, new_content)
  puts "==> Written: #{out_path}"
end

puts "\nDone! Install with:"
(1..3).each do |i|
  instance_num = i + 1
  puts "  sudo cp #{base_name}-secondary#{instance_num}.service /etc/systemd/system/"
end
puts "  sudo systemctl daemon-reload"
(1..3).each do |i|
  instance_num = i + 1
  puts "  sudo systemctl enable --now #{base_name}-secondary#{instance_num}"
end
