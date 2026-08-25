# frozen_string_literal: true
require_relative "../harness/harness-common"
require "objspace"

ObjectSpace.trace_object_allocations_start

module HeapHarness
  extend self

  def to_mib(bytes)
    "#{(bytes / 1024.0 / 1024).round(1)}MiB"
  end

  def to_kib(bytes)
    "#{(bytes / 1024.0).round(1)}kiB"
  end

  def source(obj)
    "#{obj["file"]}:#{obj["line"]} (#{obj["method"]}) "
  end

  def heap_report(file)
    require "json"

    early_evictions = Hash.new(0)
    early_evictions_mem = Hash.new(0)

    over_size = Hash.new(0)
    over_size_mem = Hash.new(0)

    ideal_sizes = 9.times.to_h do |size|
      [size, ObjectSpace.memsize_of(size.times.to_h { |i| [i, i]}.dup)]
    end
    p ideal_sizes

    count = 0
    heap_memory = 0
    malloc_memory = 0

    hash_count = 0
    hash_heap_memory = 0
    hash_malloc_memory = 0

    file.each_line do |line|
      next if line.include?('"type":"shape"')

      count += 1
      obj = JSON.parse(line)
      slot_size = obj["slot_size"]
      next unless slot_size
      memsize = obj["memsize"]
      malloc_size = (memsize - slot_size)

      heap_memory += slot_size
      malloc_memory += malloc_size

      if obj["type"] == "HASH"
        hash_count += 1
        hash_heap_memory += slot_size
        hash_malloc_memory += malloc_size

        if obj["size"] <= 8
          if malloc_size > 0
            early_evictions[source(obj)] += 1
            early_evictions_mem[source(obj)] += (obj["memsize"] - ideal_sizes[obj["size"]])
          elsif obj["memsize"] > ideal_sizes[obj["size"]]
            over_size[source(obj)] += 1
            over_size_mem[source(obj)] += (obj["memsize"] - ideal_sizes[obj["size"]])
          end
        end
      end
    end

    puts "=" * 40
    puts "#{RUBY_DESCRIPTION}:"
    puts "  #{count} objects / #{to_mib(heap_memory + malloc_memory)}"
    puts "  (malloc: #{to_mib(malloc_memory)}, heap: #{to_mib(heap_memory)})"
    puts "hashes:"
    puts "  #{hash_count} hashes / #{to_mib(hash_heap_memory + hash_malloc_memory)}"
    puts "  (malloc: #{to_mib(hash_malloc_memory)}, heap: #{to_mib(hash_heap_memory)})"
    puts
    puts "top early evictions sources"
    puts(early_evictions_mem.sort_by { |(k, v)| - v}.first(20).map { |k, v| "#{k}: #{to_kib(v)} (#{early_evictions[k]})" })
    puts
    puts "over size"
    puts(over_size_mem.sort_by { |(k, v)| - v}.first(20).map { |k, v| "#{k}: #{to_kib(v)} (#{over_size[k]})" })
    puts
    # puts "top 0 size st_table sources ()"
    # puts(zero_sized.sort_by { |(k, v)| - v}.first(20).map { |k, v| "#{k}: #{v}" })
    # puts
    puts "=" * 40
  end
end

def run_benchmark(_num)
  Process.warmup
  yield # prewarm
  GC.start
  GC.disable
  yield

  File.open("/tmp/heap.json", "w+") do |f|
    ObjectSpace.dump_all(output: f)
    f.rewind
    HeapHarness.heap_report(f)
  end

  return_results([], [0.001]) # bogus timing
end
