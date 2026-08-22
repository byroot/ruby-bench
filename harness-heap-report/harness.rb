# frozen_string_literal: true
require_relative "../harness/harness-common"
require "objspace"

ObjectSpace.trace_object_allocations_start

module HeapHarness
  extend self

  def to_mib(bytes)
    "#{(bytes / 1024.0 / 1024).round(1)}MiB"
  end

  def heap_report(file)
    require "json"

    early_evictions = Hash.new(0)

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

        if malloc_size > 0 && obj["size"] <= 8
          early_evictions["#{obj["file"]}:#{obj["line"]}"] += 1
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
    puts(early_evictions.sort_by { |(k, v)| - v}.first(20).map { |k, v| "#{k}: #{v}" })
    puts "=" * 40
  end
end

def run_benchmark(_num)
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
