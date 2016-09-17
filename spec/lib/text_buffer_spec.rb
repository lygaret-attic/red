require './spec/spec_helper'
require './lib/text_buffer'

RSpec.describe "TextBuffer" do

  context ".new" do
    it "can create an empty buffer" do
      t = TextBuffer.new
      expect(t.contents).to be_empty
    end

    it "can create a buffer with some string" do
      t = TextBuffer.new("one two three")
      expect(t.contents).to eq("one two three")
    end
  end

  context ".open" do
    it "creates a buffer with the contents of the given file" do
      t = TextBuffer.open(__FILE__)
      expect(t.contents).to eq(File.read(__FILE__))
    end

    it "raises normal file exceptions when non-existant file" do
      expect {
        TextBuffer.open("not_exist")
      }.to raise_error(Errno::ENOENT)
    end
  end
  
  context "#insert" do
    subject { TextBuffer.new("one two three") }

    it "can insert text at the beginning" do
      subject.insert("zero ", at: 0)
      expect(subject.contents).to eq("zero one two three")
    end

    it "can insert text at the end" do
      subject.insert(" four", at: subject.contents.length)
      expect(subject.contents).to eq("one two three four")
    end

    it "can insert text in the middle" do
      subject.insert(", and a", at: 3)
      expect(subject.contents).to eq("one, and a two three")
    end
  end

  context "#delete" do
    subject { TextBuffer.new("one two three") }

    it "can delete text from the beginning" do
      subject.delete(from: 0, length: 4)
      expect(subject.contents).to eq("two three")
    end

    it "can delete text from the end" do
      subject.delete(from: 7, length: 6)
      expect(subject.contents).to eq("one two")
    end

    it "can delete text from the middle" do
      subject.delete(from: 4, length: 4)
      expect(subject.contents).to eq("one three")
    end

    it "can delete after some insertions" do
      subject.insert("and a ", at: 4)
      subject.insert("and a ", at: 14)
      # "one and a two and a three"

      subject.delete(from: 7, length: 2)
      expect(subject.contents).to eq("one and two and a three")
    end
  end

  context "#undo" do
    subject { TextBuffer.new("one two three") }

    it "can undo an insertion" do
      subject.insert("blah", at: 2)
      subject.undo
      expect(subject.contents).to eq("one two three")
    end

    it "can undo multiple insertions" do
      subject.insert("what's this? ", at: 0)
      subject.insert("blah", at: 2)
      subject.insert("baz", at: 10)

      subject.undo
      subject.undo

      expect(subject.contents).to eq("what's this? one two three")
    end

    it "can undo a deletion" do
      subject.delete(from: 4, length: 4)
      subject.undo
      expect(subject.contents).to eq("one two three")
    end
  end
  
end
