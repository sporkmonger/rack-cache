require "#{File.dirname(__FILE__)}/spec_setup"
require 'rack/cache/entitystore'

class Object
  def sha_like?
    length == 40 && self =~ /^[0-9a-z]+$/
  end
end

describe_shared 'A Rack::Cache::EntityStore Implementation' do

  it 'responds to all required messages' do
    %w[read open write exist?].each do |message|
      @store.should.respond_to message
    end
  end

  it 'stores bodies with #write' do
    key, size = @store.write('My wild love went riding,')
    key.should.not.be.nil
    key.should.be.sha_like

    data = @store.read(key)
    data.should.be == 'My wild love went riding,'
  end

  it 'correctly determines whether cached body exists for key with #exist?' do
    key, size = @store.write('She rode to the devil,')
    @store.should.exist key
    @store.should.not.exist '938jasddj83jasdh4438021ksdfjsdfjsdsf'
  end

  it 'can read data written with #write' do
    key, size = @store.write('And asked him to pay.')
    data = @store.read(key)
    data.should.be == 'And asked him to pay.'
  end

  it 'gives a 40 character SHA1 hex digest from #write' do
    key, size = @store.write('she rode to the sea;')
    key.should.not.be.nil
    key.length.should.be == 40
    key.should.be =~ /^[0-9a-z]+$/
    key.should.be == '90a4c84d51a277f3dafc34693ca264531b9f51b6'
  end

  it 'returns the entire body as a String from #read' do
    key, size = @store.write('She gathered together')
    @store.read(key).should.be == 'She gathered together'
  end

  it 'returns nil from #read when key does not exist' do
    @store.read('87fe0a1ae82a518592f6b12b0183e950b4541c62').should.be.nil
  end

  it 'returns a Rack compatible body from #open' do
    key, size = @store.write('Some shells for her hair.')
    body = @store.open(key)
    body.should.respond_to :each
    buf = ''
    body.each { |part| buf << part }
    buf.should.be == 'Some shells for her hair.'
  end

  it 'returns nil from #open when key does not exist' do
    @store.open('87fe0a1ae82a518592f6b12b0183e950b4541c62').should.be.nil
  end

  it 'can store largish bodies with binary data' do
    pony = File.read(File.dirname(__FILE__) + '/pony.jpg')
    key, size = @store.write(pony)
    key.should.be == 'd0f30d8659b4d268c5c64385d9790024c2d78deb'
    data = @store.read(key)
    data.length.should.be == pony.length
    data.hash.should.be == pony.hash
  end

end

describe 'Rack::Cache::EntityStore' do

  describe 'Heap' do
    it_should_behave_like 'A Rack::Cache::EntityStore Implementation'
    before { @store = Rack::Cache::EntityStore::Heap.new }
    it 'takes a Hash to ::new' do
      @store = Rack::Cache::EntityStore::Heap.new('foo' => ['bar'])
      @store.read('foo').should.be == 'bar'
    end
    it 'uses its own Hash with no args to ::new' do
      @store.read('foo').should.be.nil
    end
  end

  describe 'Disk' do
    it_should_behave_like 'A Rack::Cache::EntityStore Implementation'
    before do
      @temp_dir = create_temp_directory
      @store = Rack::Cache::EntityStore::Disk.new(@temp_dir)
    end
    after do
      @store = nil
      remove_entry_secure @temp_dir
    end
    it 'takes a path to ::new and creates the directory' do
      path = @temp_dir + '/foo'
      @store = Rack::Cache::EntityStore::Disk.new(path)
      File.should.be.a.directory path
    end
    it 'spreads data over a 36² hash radius' do
      (<<-PROSE).each { |line| @store.write(line).first.should.be.sha_like }
        My wild love went riding,
        She rode all the day;
        She rode to the devil,
        And asked him to pay.

        The devil was wiser
        It's time to repent;
        He asked her to give back
        The money she spent

        My wild love went riding,
        She rode to sea;
        She gathered together
        Some shells for her hair

        She rode on to Christmas,
        She rode to the farm;
        She rode to Japan
        And re-entered a town

        My wild love is crazy
        She screams like a bird;
        She moans like a cat
        When she wants to be heard

        She rode and she rode on
        She rode for a while,
        Then stopped for an evening
        And laid her head down

        By this time the weather
        Had changed one degree,
        She asked for the people
        To let her go free

        My wild love went riding,
        She rode for an hour;
        She rode and she rested,
        And then she rode on
        My wild love went riding,
      PROSE
      subdirs = Dir["#{@temp_dir}/*"]
      subdirs.each do |subdir|
        File.basename(subdir).should.be =~ /^[0-9a-z]{2}$/
        files = Dir["#{subdir}/*"]
        files.each do |filename|
          File.basename(filename).should.be =~ /^[0-9a-z]{38}$/
        end
        files.length.should.be > 0
      end
      subdirs.length.should.be == 28
    end
  end

  need_memcached 'entity store tests' do
    describe 'MemCache' do
      it_should_behave_like 'A Rack::Cache::EntityStore Implementation'
      before do
        @store = Rack::Cache::EntityStore::MemCache.new($memcached)
      end
      after do
        @store = nil
      end
    end
  end
end
