Help me create a Flutter application (woxxy) that performs the following tasks:

Woxxy is a local LAN filesharing application
The protocol is not secure, but ultra fast
It is created to quickly share large files over the LAN between coworkers
Security IS NOT an issue
The app should:

At start, broadcast the LAN to meet the other Woxxy running
Allow user to select another user in the LAN and then drag & drop FILES or Directories to the user.
Show progress status


# FileTransfer class

First of all, create a new FileTransfer class lib/models/file_transfer.dart. This is an instance of a single FileTransfer, the class will have these properties:

- source_ip   (the IP the file is being transfererred from)
- destination_filename:   the filename the file has on the LOCAL fileystem
- size:  the file size in bytes
- file_sink:  the IOSink instance, this instance is created when the FileTransfer is created and it will be closed only when the transfer is complete
- duration:  a StopWatch() to measure how much time did it take for the file transfer to complete

The FileTransfer class will have these methods:

- start(source_ip, original_filename, size)

This method creates a new File in the user filesystem (the destination path is the user preferred path + original_filename, or the user home directory + "/Downloads" + original_filename if the user did not set a preferred path) and creates a new IOSink instance to write the file in binary format.

If the destination path does not exist, the method creates the path.
If the destination file already exists, the method creates a new file with a new name, adding a number to the filename (original_filename_1, original_filename_2, etc)

The method also starts the StopWatch() instance.

- write( binary_data)

This method adds the binary_data to the file_sink instance

- end()

This method closes the file_sink instance and stops the StopWatch() instance

# FileTransferManager class

Create a new FileTransferManager class lib/models/file_transfer_manager.dart.
A client can have multiple FileTransfer instances, from different sources (different IPs), so the FileTransferManager class will manage all the FileTransfer instances for a single client.

This class will have these properties:

- files:  a Map of FileTransfer instances, the key is the source_ip

This class will will have these methods:

- add (source_ip, original_filename, size)

This method creates a new FileTransfer instance and adds it to the files Map
This method also adds the FileTransfer instance to the files Map using the source_ip as the key

- write(source_ip, binary_data)

This method calls the write method of the FileTransfer instance with the source_ip key

- end(source_ip)

This method calls the end method of the FileTransfer instance with the source_ip key

