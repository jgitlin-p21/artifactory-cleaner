
RSpec.describe Artifactory::Cleaner do
  it "has a version number" do
    expect(Artifactory::Cleaner::VERSION).not_to be nil
  end

  describe Artifactory::Cleaner::ArtifactBucket do
    subject { Artifactory::Cleaner::ArtifactBucket.new(0,100) }

    it { should respond_to :each }
    it { should respond_to :slice }
    it { should respond_to :clear }
    it { should respond_to :first }
    it { should respond_to :last }

    it "knows when it is empty" do
      expect(subject.length).to eq 0
      expect(subject.empty?).to eq true
    end

    describe "using a bucket" do
      before(:all) do
        @bucket = Artifactory::Cleaner::ArtifactBucket.new(0,100)
      end

      it "artifacts can be added" do
        @bucket << generate_artifact
        @bucket.push generate_artifact
        expect(@bucket.length == 2)
      end

      it "non-artifacts are rejected" do
        expect { @bucket << "test" }.to raise_error(TypeError)
        expect { @bucket << 1 }.to raise_error(TypeError)
        expect { @bucket << nil }.to raise_error(TypeError)
        expect { @bucket << {} }.to raise_error(TypeError)
        expect { @bucket << [] }.to raise_error(TypeError)
      end

      it "tracks filesize" do
        expected_size = @bucket.filesize
        10.times do
          artifact = generate_artifact
          expected_size += artifact.size
          @bucket << artifact
          expect(@bucket.filesize).to eq expected_size
        end
      end

      it "bucket is enumerable" do
        @bucket.each do |artifact|
          expect artifact.is_a? Artifactory::Cleaner::DiscoveredArtifact
        end
      end

      it "recalculates filesize corectly" do
        calculated_filesize = @bucket.filesize
        recalculated_filesize = @bucket.recalculate_filesize
        expect(recalculated_filesize).not_to eq 0
        expect(recalculated_filesize).to eq calculated_filesize
      end
    end
  end

  describe Artifactory::Cleaner::ArtifactBucketCollection do
    subject(:bucket_collection) { Artifactory::Cleaner::ArtifactBucketCollection.new }

    it { should respond_to :each }
    it { should respond_to :length }
    it { should respond_to :clear }
    it { should respond_to :first }
    it { should respond_to :last }

    it "has buckets" do
      expect(subject.bucket_sizes).to be_an(Array)
      expect(subject.bucket_sizes).not_to be_empty
    end

    it "accepts artifacts" do
      subject << generate_artifact
    end

    it "is enumerable" do
      subject.each do |bucket|
        expect bucket.is_a? Artifactory::Cleaner::ArtifactBucket
      end
    end

    # TODO: This test intermittently fails. There may be an issue with it!
    #   1) Artifactory::Cleaner Artifactory::Cleaner::ArtifactBucketCollection handles various bucket sizes
    #      Failure/Error: expect(collection[bucket_size].max).to eq bucket_max
    #
    #        expected: 0
    #             got: 129
    #
    #        (compared using ==)
    #      # ./spec/artifactory/cleaner_spec.rb:97:in `block (5 levels) in <top (required)>'
    #      # ./spec/artifactory/cleaner_spec.rb:94:in `each'
    #      # ./spec/artifactory/cleaner_spec.rb:94:in `block (4 levels) in <top (required)>'
    #      # ./spec/artifactory/cleaner_spec.rb:90:in `times'
    #      # ./spec/artifactory/cleaner_spec.rb:90:in `block (3 levels) in <top (required)>'
    it "handles various bucket sizes" do
      5.times do
        buckets = 10.times.map {|i| (rand*99).floor + i*100}
        collection = Artifactory::Cleaner::ArtifactBucketCollection.new(buckets)
        bucket_size = 0
        buckets.each do |bucket_max|
          expect(collection[bucket_size]).to be_an(Artifactory::Cleaner::ArtifactBucket)
          expect(collection[bucket_size].min).to eq bucket_size
          expect(collection[bucket_size].max).to eq bucket_max
          bucket_size = bucket_max
        end
      end
    end

    describe '.artifact_count' do
      it "gives an accurate count" do
        initial_length = bucket_collection.artifact_count
        expected_length = initial_length
        100.times do |i|
          artifact = generate_artifact
          bucket_collection << artifact
          expected_length = expected_length + 1
          expect(bucket_collection.artifact_count).to eq expected_length
        end
      end
    end

    context "when artifacts are added" do
      it "selects the correct buckets" do
        bucket_collection.bucket_sizes.each do |age|
          next if age == Float::INFINITY
          10.times do
            artifact = generate_artifact
            artifact.last_downloaded = Time.now - (age*24*3600) - (rand*3600*24)
            artifact.last_modified = Time.now - (age*24*3600) - (rand*3600*24)
            artifact.created = Time.now - (age*24*3600) - ((rand+1)*3600*24)
            bucket_size = bucket_collection[age].length
            bucket_collection << artifact
            expect(bucket_collection[age].length).to eq bucket_size+1
          end
        end
      end
    end
  end

  describe Artifactory::Cleaner::ArtifactFilterRule do
    #subject { Artifactory::Cleaner::ArtifactFilterRule.new() }
    it "allows setting the regex" do
      subject.regex = %r{.*/opencdisc/.*/4\.[.0-9]+/.*}
      subject.regexp = %r{.*/opencdisc/.*/3\.[456789]\.[.0-9]+/.*}
    end
  end

  describe Artifactory::Cleaner::ArtifactFilter do
    #subject { Artifactory::Cleaner::ArtifactFilterRule.new() }

    it { should respond_to :each }
    it { should respond_to :slice }
    it { should respond_to :clear }
    it { should respond_to :first }
    it { should respond_to :last }

    it "knows when it is empty" do
      expect(subject.length).to eq 0
      expect(subject.empty?).to eq true
    end

    describe "using a filter" do
      before(:all) do
        @filter = Artifactory::Cleaner::ArtifactFilter.new
      end

      it "rules can be added" do
        @filter << generate_rule
        @filter.push(generate_rule)
        expect(@filter.length == 2)
      end

      it "non-rules are rejected" do
        expect { @filter << "test" }.to raise_error(TypeError)
        expect { @filter << 1 }.to raise_error(TypeError)
        expect { @filter << nil }.to raise_error(TypeError)
        expect { @filter << {} }.to raise_error(TypeError)
        expect { @filter << [] }.to raise_error(TypeError)
      end

      it "is enumerable" do
        @filter.each do |rule|
          expect rule.is_a? Artifactory::Cleaner::ArtifactFilterRule
        end
      end

      it "sorts automatically" do
        50.times do
          @filter << generate_rule
        end
        last_priority = nil
        @filter.each do |rule|
          expect(rule.priority).to be >= last_priority unless last_priority.nil?
          last_priority = rule.priority
        end
      end

      it "accepts in priority order" do
        filter = Artifactory::Cleaner::ArtifactFilter.new
        filter << Artifactory::Cleaner::ArtifactFilterRule.new(action: :exclude, priority: 1, regex: /.*/)
        filter << Artifactory::Cleaner::ArtifactFilterRule.new(action: :include, priority: 0, regex: /.*/)
        expect(filter.action_for(generate_artifact)).to eq :include
      end

      it "rejects in priority order" do
        filter = Artifactory::Cleaner::ArtifactFilter.new
        filter << Artifactory::Cleaner::ArtifactFilterRule.new(action: :include, priority: 2, regex: /.*/)
        filter << Artifactory::Cleaner::ArtifactFilterRule.new(action: :exclude, priority: 1, regex: /.*/)
        expect(filter.action_for(generate_artifact)).to eq :exclude
      end

      it "accepts as a default" do
        filter = Artifactory::Cleaner::ArtifactFilter.new
        filter << Artifactory::Cleaner::ArtifactFilterRule.new(action: :exclude, priority: 1, regex: /do not match/)
        filter << Artifactory::Cleaner::ArtifactFilterRule.new(action: :include, priority: 0, regex: /do not match/)
        expect(filter.action_for(generate_artifact)).to eq :include
      end
    end
  end
end

