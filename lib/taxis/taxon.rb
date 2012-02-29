require 'nested_set'
require 'stringex'
module Taxis
  class Taxon < ActiveRecord::Base


    acts_as_nested_set :dependent => :destroy

    acts_as_url :name, :sync_url => true


    belongs_to :taxonomy
    has_many :taxon_items

    before_create :set_path, :set_taxonomy
    after_create :set_root
    before_update :set_path



    # TODO: I don't love this implementation as it doesn't allow for effective navigation up the tree
    # but it does provide a nice url breadcrumb trail


    # Creates path based on .to_url method provided by stringx gem
    def set_path

      if self.root? 
        self.path = '/' 
      else
        ancestor_path = parent_taxon.path rescue "/"
        sep = ancestor_path == "/" ? "" : "/"
        self.path = ancestor_path + sep + self.url
      end

    end

    def set_taxonomy
      if ! self.root?
        self.root_id = parent_taxon.root_id
        self.taxonomy_id = parent_taxon.taxonomy_id
      end
    end

    def set_root
      self.root_id = self.id if self.root?
      save
    end


    # Attaches any ActiveRecord class to a taxon
    def attach(klass)
      self.taxon_items.create(:taxonable_type => klass.class.to_s, :taxonable_id => klass[:id])
      klass.reload
      self.reload
      return klass
    end

    # Removes an attached ActiveRecord object from a taxon
    def detach(klass)
      ti = self.taxon_items.where(:taxonable_type => klass.class.to_s, :taxonable_id => klass[:id]).first
      ti.delete if ti
      klass.reload
      self.reload
      return klass
    end

    def attach_by_param(class_name, row_id)
      return manage_by_param(:attach, class_name, row_id)
    end

    def detach_by_param(class_name, row_id)
      return manage_by_param(:detach, class_name, row_id)
    end

    def tree_children
      children = []
      self.children.each do |taxon|
        children << {
          :attr => {:id => taxon.id.to_s},
          :data => taxon.name,
          :state => taxon.children.empty? ? "" : "closed"
        }
      end
      
      return children
    end

    def method_missing(obj, *args)
      if obj.match(/attached_(.*)/)
        table_name = $1
        class_name = table_name.classify
        klass = get_klass(class_name)
        if klass
          records = klass.find_by_sql <<-SQL
            SELECT n.* 
            FROM #{table_name} n 
            JOIN taxon_items ti ON ti.taxonable_id = n.id AND taxonable_type = '#{class_name}'
          SQL
        else
          raise "Unknown attached class name '#{class_name}'"
        end

        return records || []

      else
        super
      end
    end



    private

    def parent_taxon
      @parent_taxon ||= Taxon.find(self.parent_id)
    end


    def manage_by_param(method, class_name, row_id)
      klass = get_klass(class_name)
      if klass
        row = klass.find_by_id row_id
        if row
          if method == :attach
            attach(row)
          elsif method == :detach
            detach(row)
          else
            raise "Unknown method"
          end
        else
          raise "#{class_name} record does not exist."
        end

      else
        raise "Invalid class name '#{class_name}'"
      end
      return row
    end

    def get_klass(class_name)
      klass = Kernel.const_get(class_name)
      return klass.respond_to?('find_by_sql') ? klass : nil
    end



  end

end
