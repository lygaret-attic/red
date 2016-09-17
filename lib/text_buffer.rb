require './lib/assert'

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

  Piece = Struct.new("Piece", :buffer, :offset, :length) 
  Coord = Struct.new("Coord", :piece, :index, :offset)

  class Buffer

    def initialize(text)
      @buffers = {
        file:   text.freeze,
        append: ""
      }

      @chain  = [Piece.new(:file, 0, text.length)]
      @undo   = []
    end

    # to get string contents for the buffer, walk the chain

    def contents
      content  = @chain.map do |p|
        buffer = @buffers[p.buffer]
        assert("unknown buffer type in chain")  { !buffer.nil? }
        assert("invalid piece length in chain") { p.offset + p.length <= buffer.length }

        buffer[p.offset, p.length]
      end

      content.join
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
      offset = @buffers[:append].length
      @buffers[:append] += text

      offset
    end

    private def insert_beginning(text, coord)
      offset = insert_text(text)
      @chain[coord.index, 0] = Piece.new(:append, offset, text.length)
    end

    private def insert_end(text, coord)
      offset = insert_text(text)
      @chain[coord.index + 1, 0] = Piece.new(:append, offset, text.length)
    end

    private def insert_middle(text, coord)
      offset = insert_text(text)
      split_chain(at: coord, insert: Piece.new(:append, offset, text.length))
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
      @chain.slice! sindex...eindex
    end

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
