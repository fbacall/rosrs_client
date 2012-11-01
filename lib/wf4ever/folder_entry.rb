module Wf4Ever

  # An item within a folder.

  class FolderEntry

    attr_reader :folder, :name, :uri, :entry_uri

    ##
    # +folder+:: A Wf4Ever::Folder object in which this entry resides..
    # +name+:: The display name of the FolderEntry.
    # +uri+:: The URI for the resource referred to by the FolderEntry.
    # +entry_uri+:: The URI of the folder entry.
    def initialize(folder, name, uri, entry_uri, options = {})
      @name = name
      @uri = uri
      @entry_uri = entry_uri
      @folder = folder
      @is_folder = options[:is_folder]
      @session = @folder.research_object.session
    end

    ##
    # Returns boolean stating whether or not this entry points to a folder
    def folder?
      @is_folder
    end

    ##
    # Removes this entry from the folder. The resource it refers to will still exists, however.
    def delete!
      @session.remove_folder_entry(@entry_uri)
      true
    end

  end

end