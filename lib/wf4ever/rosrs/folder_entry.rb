module ROSRS

  # An item within a folder.

  class FolderEntry

    attr_reader :parent_folder, :name, :uri, :resource

    ##
    # +parent_folder+:: The ROSRS::Folder object in which this entry resides..
    # +name+::          The display name of the ROSRS::FolderEntry.
    # +uri+::           The URI of this ROSRS::FolderEntry
    # +resource_uri+::  The URI for the resource referred to by this ROSRS::FolderEntry.
    # +folder+::        (Optional) The ROSRS::Folder that this entry points to, if applicable.
    def initialize(parent_folder, name, uri, resource_uri, folder = nil)
      @uri = uri
      @name = name
      @folder = folder
      @parent_folder = parent_folder
      @session = @parent_folder.research_object.session
      @resource = @parent_folder.research_object.resources(resource_uri) ||
                  @parent_folder.research_object.folders(resource_uri) ||
                  ROSRS::Resource.new(@parent_folder.research_object, resource_uri)
    end

    ##
    # Removes this folder entry from the folder. Does not delete the resource.
    def delete
      code = @session.delete_resource(@uri)[0]
      @loaded = false
      code == 204
    end

    ##
    # Returns boolean stating whether or not this entry points to a folder
    #def folder?
    #  @is_folder
    #end

    def self.create(parent_folder, name, resource_uri)
      code, reason, uri = parent_folder.research_object.session.add_folder_entry(parent_folder.uri, resource_uri, name)
      self.new(parent_folder, name, uri, resource_uri)
    end

  end

end