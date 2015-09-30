module Cap
  module Vivo
    module Orgs

      HAS_CONTACT_INFO = RDF::URI.parse 'http://purl.obolibrary.org/obo/ARG_2000028'

      # Resolve an organization name into a VIVO representation
      # @parameter org_name [String] an organization name
      # @return vivo_rdf [RDF::Graph]
      def org_strings2things(org_name)
        case org_name
        when /stanford.*(library|libraries)/i
          stanford_libraries
        when /stanford medical school/i
          stanford_medical_school
        else
          unknown_org(org_name)
        end
      end

      # Create a VIVO organization graph, identified by
      # foaf:Organization and vcard:Organization data.
      # @param org_uri [RDF::URI]
      # @param org_name [String]
      # @return graph [RDF::Graph]
      def org_graph(org_uri, org_name)
        g = org_foaf(org_uri, org_name)
        uri = RDF::URI.parse org_uri.to_s.chomp('/')
        vcard_uri = uri + '/vcard'
        g << org_vcard(org_uri, vcard_uri)
        g << org_vcard_name(vcard_uri, org_name)
        g
      end

      # Add a foaf:Organization to graph
      # @param org_uri [RDF::URI]
      # @param foaf_uri [RDF::URI]
      # @return graph [RDF::Graph]
      def org_foaf(org_uri, org_name)
        g = RDF::Graph.new
        g << [org_uri, RDF.type, RDF::FOAF.Organization]
        g << [org_uri, RDF::FOAF.name, org_name]
        g
      end

      # Add a vcard:Organization to graph
      # @param org_uri [RDF::URI]
      # @param vcard_uri [RDF::URI]
      # @return graph [RDF::Graph]
      def org_vcard(org_uri, vcard_uri)
        g = RDF::Graph.new
        g << [org_uri, HAS_CONTACT_INFO, vcard_uri]
        g << [vcard_uri, RDF.type, RDF::VIVO_VCARD.Organization]
        g
      end

      # Add a vcard:Name to graph
      # @param vcard_uri [RDF::URI]
      # @param org_name [String]
      # @return graph [RDF::Graph]
      def org_vcard_name(vcard_uri, org_name)
        vcard_name = vcard_uri + '/name'
        g = RDF::Graph.new
        g << [vcard_uri, RDF::VIVO_VCARD.hasName, vcard_name]
        g << [vcard_name, RDF.type, RDF::VIVO_VCARD.Name]
        g << [vcard_name, RDF::VIVO_VCARD.givenName, org_name]
        g
      end

      # Add a VCard URL to graph
      # @param g [RDF::Graph]
      # @param vcard_link_uri [RDF::URI]
      # @param org_link_uri [RDF::URI]
      # @param org_label [String] description for org_link_uri
      # @return graph [RDF::Graph]
      def org_vcard_link(vcard, vcard_link_uri, org_link_uri, org_label=nil)
        g = RDF::Graph.new
        g << [vcard, RDF::VIVO_VCARD.hasURL, vcard_link_uri]
        g << [vcard_link_uri, RDF::VIVO_VCARD.url, org_link_uri]
        g << [vcard_link_uri, RDF::RDFS.label, org_label] if org_label
        g
      end

      # Query an RDF::Graph for an organization vcard
      # @param g [RDF::Graph] an organization graph
      # @param vcard_uri [RDF::URI|nil] a vcard URI
      def vcard_from_graph(g)
        q = [nil, RDF.type, RDF::VIVO_VCARD.Organization]
        g.query(q).first.subject rescue nil
      end

      # Create a rudimentary VIVO representation for an organization name
      # @parameter org_name [String] an organization name
      # @return vivo_rdf [RDF::Graph]
      def unknown_org(org_name)
        name = org_name.gsub(/\W+/,'').downcase
        org_uri = RDF::URI.parse "http://vivo.stanford.edu/org/#{name}/"
        org_graph(org_uri, org_name)
      end

      def stanford_university
        @@stanford_university ||= begin
          org_name = "Stanford Univerity"
          org_uri = RDF::URI.parse 'http://www.stanford.edu/'
          g = org_graph(org_uri, org_name)
          g << [org_uri, RDF.type, RDF::VIVO.School]
          vcard = vcard_from_graph(g)
          link = vcard + "/link"
          link_uri = RDF::URI.parse org_uri.to_s.chomp('/')
          link_label = org_name + " Website"
          g << org_vcard_link(vcard, link, link_uri, link_label)
          g
        end
      end

      def stanford_libraries
        @@stanford_libraries ||= begin
          org_name = "Stanford Univerity Libraries"
          org_uri = RDF::URI.parse 'http://library.stanford.edu/'
          g = org_graph(org_uri, org_name)
          vcard = vcard_from_graph(g)
          link = vcard + "/link"
          link_uri = RDF::URI.parse org_uri.to_s.chomp('/')
          link_label = org_name + " Website"
          g << org_vcard_link(vcard, link, link_uri, link_label)
          g
        end
      end

      def stanford_medical_school
        @@stanford_medical_school ||= begin
          org_name = "Stanford Univerity Medical School"
          org_uri = RDF::URI.parse('http://med.stanford.edu/')
          loc_uri = RDF::URI.parse('http://id.loc.gov/authorities/names/n79091625.rdf')
          g = org_graph(org_uri, org_name)
          g << [org_uri, RDF.type, RDF::VIVO.School]
          vcard = vcard_from_graph(g)
          link = vcard + "/link"
          link_uri = RDF::URI.parse org_uri.to_s.chomp('/')
          link_label = org_name + " Website"
          g << org_vcard_link(vcard, link, link_uri, link_label)
          link = vcard + "/loc"
          link_label = "LOC Name Authority File"
          g << org_vcard_link(vcard, link, loc_uri, link_label)
          g
          #     vcard:hasAddress [
          #         a vcard:Address, vcard:Work;
          #         vcard:country-name "United States";
          #         vcard:region "California";
          #         vcard:locality "Stanford";
          #         vcard:postal-code "94305";
          #         vcard:street-address "Medical School, Stanford" .
          #     vcard:hasTelephone [
          #         a vcard:Telephone, vcard:Work, vcard:Voice;
          #         vcard:telephone <tel:+6509999999> .
          #     # TODO: use vivo:Campus ????
          #     # TODO: Associate school of medicine with Stanford U ????
        end
      end

    end
  end
end
