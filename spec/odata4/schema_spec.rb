require 'spec_helper'

describe OData4::Schema do
  let(:subject) { OData4::Schema.new(schema_xml, service) }
  let(:service) do
    OData4::Service.open('http://services.odata.org/V4/OData/OData.svc', metadata_file: metadata_file)
  end
  let(:metadata_file) { 'spec/fixtures/files/metadata.xml' }
  let(:schema_xml) { service.metadata.xpath('//Schema').first }

  let(:entity_types) { %w{Product FeaturedProduct ProductDetail Category Supplier Person Customer Employee PersonDetail Advertisement} }
  let(:complex_types) { %w{Address} }
  let(:enum_types) { %w{ProductStatus} }

  describe '#namespace' do
    it { expect(subject).to respond_to(:namespace) }
    it "returns the schema's namespace attribute" do
      expect(subject.namespace).to eq('ODataDemo')
    end
  end

  describe '#actions' do
    # TODO add a action definition to metadata
    it { expect(subject).to respond_to(:actions) }
    it { expect(subject.actions.size).to eq(0) }
  end

  describe '#annotations' do
    # TBD
  end

  describe '#complex_types' do
    it { expect(subject).to respond_to(:complex_types) }
    it { expect(subject.complex_types.size).to eq(1) }
    it { expect(subject.complex_types.keys).to eq(complex_types) }
  end

  describe '#entity_types' do
    it { expect(subject).to respond_to(:entity_types) }
    it { expect(subject.entity_types.size).to eq(10) }
    it { expect(subject.entity_types).to eq(entity_types) }
  end

  describe '#enum_types' do
    it { expect(subject).to respond_to(:enum_types) }
    it { expect(subject.enum_types.size).to eq(1) }
    it { expect(subject.enum_types.keys).to eq(enum_types)}
  end

  describe '#functions' do
    # TODO add a function definition to metadata
    it { expect(subject).to respond_to(:functions) }
    it { expect(subject.functions.size).to eq(0) }
  end

  describe '#terms' do
    # TBD
  end

  describe '#type_definitions' do
    # TODO add a type definition to metadata
    it { expect(subject).to respond_to(:type_definitions) }
    it { expect(subject.type_definitions.size).to eq(0) }
  end

end