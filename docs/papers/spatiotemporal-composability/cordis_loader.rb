# frozen_string_literal: true

# The component loader (§5.2): declarative configuration over the calculus,
# and the hot-module-replacement algorithms.
#
# An orchestrator describes the desired composition as entries (Definition
# 74); the loader translates changes to that record into fiber operations,
# applying the least disruptive operation per changed field (§5.2.1).
# Reconciling incrementally is sound because Theorem 73 makes the quiescent
# state a function of the final configuration alone, Theorem 66 proves the
# system quiesces, and Corollary 62 puts a departing fiber's contribution to
# the state at nothing.

require_relative "cordis_calculus"

module Cordis
  module Loader
    # Definition 74 — an entry declares a single fiber: a stable id (the
    # reconciliation key), the component to instantiate (here a builder
    # applied to config, standing in for the url's module), the config bound
    # into the effect function, and the administrative disabled flag.
    Entry = Struct.new(:id, :builder, :config, :disabled, keyword_init: true) do
      def component = builder.call(config)
    end

    # The loader keeps the configuration tree authoritative: reconcile diffs
    # the new entries against what is loaded, dispatches per field, and runs
    # the machine to quiescence.
    class Reconciler
      attr_reader :machine

      def initialize(machine = Calculus::Machine.new)
        @machine = machine
        @loaded = {} # id => Entry
      end

      def reconcile(entries)
        desired = entries.to_h { |e| [e.id, e] }
        (@loaded.keys - desired.keys).each { |id| remove(id) }
        desired.each { |id, entry| reconcile_entry(id, entry) }
        @machine.run
        self
      end

      private

      # Per-field dispatch (§5.2.1): a changed config or component rebuilds
      # the entry — the least disruptive operation that realizes the new
      # record; disabled unloads the fiber when set and reloads it when
      # cleared; an unchanged entry is left exactly as it stands.
      def reconcile_entry(id, entry)
        previous = @loaded[id]
        if previous.nil?
          insert(entry) unless entry.disabled
        elsif material_change?(previous, entry)
          remove(id)
          insert(entry) unless entry.disabled
        end
        @loaded[id] = entry
      end

      def material_change?(previous, entry)
        previous.config != entry.config || previous.builder != entry.builder ||
          previous.disabled != entry.disabled
      end

      def insert(entry)
        @machine.o_insert(entry.id, entry.component)
      end

      # A rebuild withdraws what the fiber installed and leaves the fibers
      # around it as they were (Corollary 62): retire, drive to Inactive,
      # remove — O-Remove's premises are what make the order safe.
      def remove(id)
        return unless @machine.fibers.key?(id)

        @machine.o_retire(id)
        @machine.run
        @machine.fibers.keys.select { |n| n == id || n.start_with?("#{id}/") }.reverse_each do |name|
          @machine.o_remove(name) if removable?(name)
        end
        @loaded.delete(id)
      end

      def removable?(name)
        fiber = @machine.fibers[name]
        fiber&.retired && fiber.state == :inactive && @machine.fibers.none? { |_, f| f.parent == name }
      end
    end

    # ---------------------------------------------------------------------
    # Hot module replacement (§5.2.2) — the pure phases.
    # imports: url → the modules that url directly imports.
    # ---------------------------------------------------------------------
    module HMR
      module_function

      # Algorithm 8 — module classification. Seeded with the imports of the
      # stashed files, the fixed point accepts a module once one of its
      # imports is accepted and declines one once all of its imports are
      # declined; anything left undecided (an import cycle) defaults to
      # declined.
      def classify(stashed, externals, imports)
        accepted = stashed.dup
        declined = externals.dup
        pending = []
        stashed.each { |url| pending |= imports.fetch(url, []) - (accepted | declined) }
        loop do
          progress = false
          pending.dup.each do |url|
            deps = imports.fetch(url, [])
            if deps.intersect?(accepted)
              accepted |= [url]
              pending -= [url]
              progress = true
            elsif (deps - declined).empty?
              declined |= [url]
              pending -= [url]
              progress = true
            else
              pending |= deps - (accepted | declined)
            end
          end
          break unless progress
        end
        [accepted, declined | pending]
      end

      # Algorithm 9 — stale-entry detection: the transitive imports of an
      # entry's module, respecting declined as a boundary; an entry is stale
      # exactly when its tree intersects accepted, and that tree is then
      # folded into accepted.
      def dependencies(root, declined, imports)
        deps = []
        traverse = lambda do |url|
          return if deps.include?(url) || declined.include?(url)

          deps << url
          imports.fetch(url, []).each { |child| traverse.call(child) }
        end
        traverse.call(root)
        deps
      end

      def detect(entry_urls, accepted, declined, imports)
        accepted = accepted.dup
        stale = []
        entry_urls.each do |url|
          tree = dependencies(url, declined, imports)
          next unless tree.intersect?(accepted)

          accepted |= tree
          stale << url
        end
        [stale, accepted]
      end
    end
  end
end
