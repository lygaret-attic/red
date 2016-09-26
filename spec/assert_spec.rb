require './spec/spec_helper'
require './lib/assert'

RSpec.describe Assert do
  context "RealAssert" do
    subject { Assert::RealAssert.instance }
    
    it "asserts on failure" do
      expect {
        subject.assert("message") { || false }
      }.to raise_error Assert::AssertionError, /message/
    end

    it "doesn't assert on success" do
      expect {
        subject.assert("message") { || true }
      }.not_to raise_error
    end
  end

  context "NullAssert" do
    subject { Assert::NullAssert.instance }

    it "doesn't assert on failure" do
      expect {
        subject.assert("message") { || false }
      }.not_to raise_error
    end

    it "doesn't assert on success" do
      expect {
        subject.assert("message") { || true }
      }.not_to raise_error
    end

    it "doesn't call it's block" do
      called = false
      subject.assert("message") { || called = true }
      expect(called).to eq(false)
    end
  end
end
