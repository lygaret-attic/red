require './lib/assert'
require './lib/logger'

module TextBuffer

  # A text buffer, implemented with a piece chain
  #
  # This data structure consists of:
  # - 2 buffers for textual data
  #   - a read-only "file" buffer, which represents the text in persistent storage
  #   - an append-only buffer, representing text added to the buffer during editing operations
  # - a "piece chain", an ordered collection of "text pieces", representing spans of data in
  #   the buffers
  # - an "undo stack", a stack of modifications to the piece chain which enables undo
  #
  # Constructing the textual content of the buffer requires iterating through the piece chainmmap
  # in order, and returning the text from the buffers referred to in the piece.

  class Buffer

    Piece     = Struct.new("Piece", :buffer, :offset, :length)
    Coord     = Struct.new("Coord", :piece, :index, :offset)
    LineCache = Struct.new("LineCache", :offset, :count)

    PAGESIZE  = 4096

    def initialize(text)
      @buffers = {
        file:   text.freeze,
        append: ""
      }

      @undo   = []

      @chain  = build_chain
      @lines  = [0]
    end

    # build the chain
    # initially, we create a single piece in the chain to represent each PAGESIZE of the text
    def build_chain
      page_count  = @buffers[:file].length / PAGESIZE
      last_remain = @buffers[:file].length % PAGESIZE
      last_offset = @buffers[:file].length - last_remain

      chain  = page_count.times.collect { |n| Piece.new(:file, n * PAGESIZE, PAGESIZE) }
      chain << Piece.new(:file, last_offset, last_remain)
    end

    def inspect
      "TextBuffer::Buffer"
    end

    # to get string contents for the buffer, walk the chain

    def contents
      each_line.force.join
    end

    def each_span(from: 0)
      @chain.lazy
        .drop_while { |p| (from -= p.length) > 0 }
        .map        { |p| @buffers[p.buffer][p.offset + from, p.length - from] }
    end

    def lazy_lines(from: 0)
      assert("line #{from} is underflow") { || from >= 0 }

      line_index  = [@lines.length - 1, from].min
      line_offset = @lines[line_index] + 1
      coord       = find_coord(at: line_offset)
        
      line_accum  = []
      chain       = @chain.drop(coord.index).to_enum.with_index(line_index)

      Enumerator::Lazy.new(chain) do |yielder, piece, index|
        next unless index >= from

        offset = index == 0 ? coord.offset : 0

        index  = 0
        length = 0

        @buffers[piece.buffer][piece.offset + offset, piece.length - offset].each_codepoint do |cp|
          length += 1
          if cp == 0x0A
            yielder << line_accum.pack("U*")
            line_accum.clear
          end
        end

        # after last piece, yield the rest of the text
        if @chain.last == piece && !line_accum.empty?
          yielder << line_accum.pack("U*")
        end
      end
    end

    def each_line(from: 0)
      assert("line #{from} is underflow") { || from >= 0 }

      # line_offset      is the closest line to requested
      # codepoint_offset is codepoint at which line_offset line starts

      line_index  = [@lines.length - 1, from].min
      line_offset = @lines[line_index] + 1

      # we can skip over buffer pieces to the requested codepoint offset
      # NOTE:
      # line_inset will be the inset from the beginning of the new first
      # piece after this is complete.

      piece_inset = line_offset - 1
      pieces = @chain.drop_while do |p|
        if piece_inset >= p.length
          piece_inset -= p.length
          true
        else
          false
        end
      end

      # flat map the pieces into a stream of codepoints
      # and position at the first codepoint in the requested line
      
      codepoints = pieces.lazy.flat_map { |p| @buffers[p.buffer][p.offset, p.length].each_codepoint.lazy }
      codepoints = codepoints.drop(piece_inset)
      
      # now, chunk the stream into lines
      # concurrently, update the line cache as we go

      chunked = codepoints.each_with_index.chunk do |c, index|
        index += line_offset # fix our codepoint position with what we dropped
        begin
          line_offset
        ensure
          if c == 0x0a
            line_offset += 1
            if index > @lines.last
              @lines << index
              RedLogger.logger.info "added new line #{@lines.length} @ #{index + 1}"
            end
          end
        end
      end

      # now, drop the number of lines I we skipped
      lines = chunked.drop(from - line_index)

      # finally, extract the text
      lines.map do |linum, cp|
        cp.map { |(c, _)| c }.pack("U*")
      end
    end

    # insert into the buffer breaks into three situations
    #
    # 1. insertion is at exact beginning of a piece
    #    insert a new piece in front of the piece for the new content
    #
    # 2. insertion is at exact end of a piece
    #    ? piece represents the end of the append buffer
    #       t: increate piece length
    #       f: add new piece to end
    #
    # 3. insertion breaks a piece
    #    replace piece with three that represent the prefix, new content and suffix

    def insert(text, at:)
      coord = find_coord(at: at)
      assert("buffer overflow") { !coord.nil? }

      if coord.offset == 0
        insert_beginning(text, coord)
      elsif coord.offset == coord.piece.length
        insert_end(text, coord)
      else
        insert_middle(text, coord)
      end
    end

    private def insert_text(text)
      @buffers[:append] += text
      @buffers[:append].length - text.length
    end

    private def insert_beginning(text, coord)
      offset = insert_text(text)
      @chain[coord.index, 0] = Piece.new(:append, offset, text.length)

      @undo << -> () { @chain.slice!(coord.index) }
    end

    private def insert_end(text, coord)
      offset = insert_text(text)
      @chain[coord.index + 1, 0] = Piece.new(:append, offset, text.length)

      @undo << -> () { @chain.slice!(coord.index + 1) }
    end

    private def insert_middle(text, coord)
      offset = insert_text(text)
      split_chain(at: coord, insert: Piece.new(:append, offset, text.length))

      @undo << -> () { @chain.slice!(coord.index + 1) }
    end

    # delete from the buffer breaks into four situations
    # 
    # 1. delete starts at a boundary
    # 2. delete starts midway through a piece, in which case we need to split
    # 3. delete ends at a boundary
    # 4. delete ends midway throught a piece, in which case we need to split
    #
    # additionally, delete can span multiple pieces
    #
    # 1. make a cut in the chain at from:
    # 2. make a cut in the chain at from: + length:
    # 3. remove intermediate pieces

    def delete(from:, length:)
      scoord = find_coord(at: from)
      assert("deleting from past end of buffer") { !(scoord.nil?) }
      
      sindex = scoord.index
      if scoord.offset != 0
        split_chain(at: scoord)
        sindex = sindex + 1 # split, so delete the second half
      end

      ecoord = find_coord(at: from + length)
      assert("deleting past end of buffer") { !(ecoord.nil?) }

      eindex = ecoord.index
      if ecoord.offset != 0
        split_chain(at: ecoord)
        eindex = eindex + 1 # split, so delete UP TO the second half
      end

      # remove the dead pieces
      removed = @chain.slice! sindex...eindex
      @undo << -> () { @chain[sindex, 0] = removed }
    end

    # undo/redo

    def undo
      return unless @undo.length > 0
      @undo.length && @undo.pop.call
    end

    # utilities

    private def find_coord(at:)
      index = @chain.find_index { |p| (at -= p.length) <= 0 }
      index.nil? ? nil : Coord.new(@chain[index], index, @chain[index].length + at)
    end

    private def split_chain(at:, insert: nil)
      prefix  = Piece.new(at.piece.buffer, at.piece.offset, at.offset)
      suffix  = Piece.new(at.piece.buffer, at.piece.offset + at.offset, at.piece.length - at.offset)

      if insert.nil?
        @chain[at.index,     1] = prefix
        @chain[at.index + 1, 0] = suffix
      else
        @chain[at.index,     1] = prefix
        @chain[at.index + 1, 0] = insert
        @chain[at.index + 2, 0] = suffix
      end
    end

  end

  def self.new(text = "")
    Buffer.new(text)
  end

  def self.open(path)
    Buffer.new(File.read(path))
  end
end
