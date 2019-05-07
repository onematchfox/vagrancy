require 'fileutils'
require 'pathname'

module Vagrancy
  class Filestore

    def initialize(base_path, temp_path)
      @base_path = base_path
      @temp_path = temp_path
    end

    def exists?(file)
      File.exists?(file_path(file))
    end

    def file_path(file)
      full_path = File.expand_path(File.join(@base_path, file))
      raise Vagrancy::InvalidFilePath.new "access denied for path #{file}" unless Pathname.new(full_path).fnmatch? File.join(@base_path, '**')
      full_path
    end

    def directories_in(path)
      Dir.glob("#{file_path(path)}/*").select {|d| File.directory? d}.collect do |entry|
        File.basename entry
      end
    end

    # Safely writes by locking
    def write(file, io_stream, logger)
      with_parent_directories_created(file) do
        transactionally_write(file, io_stream, logger)
      end
    end

    def read(file)
      File.read(file_path(file))
    end

    def delete(file)
      File.unlink(file_path(file))
    end


    private

    def with_parent_directories_created(file)
      base_directory = File.dirname(file_path(file))
      FileUtils.mkdir_p base_directory unless Dir.exists? base_directory
      temp_directory  = File.dirname(temp_path(file))
      FileUtils.mkdir_p temp_directory unless Dir.exists? temp_directory
      yield
    end

    def transactionally_write(file, io_stream, logger)
      within_file_lock(file) do
        begin
          transaction_file = File.open("#{temp_path(file)}.txn", File::RDWR|File::CREAT, 0644)
          IO.copy_stream(io_stream, transaction_file)
          transaction_file.flush
          logger.info "Upload complete - Temp file: #{temp_path(file)}.txn"
          FileUtils.mv(transaction_file.path, "#{file_path(file)}")
          logger.info "Move complete"
        ensure
          transaction_file.close
          File.unlink("#{temp_path(file)}.txn") if File.exists?("#{temp_path(file)}.txn")
        end
      end
    end

    def within_file_lock(file)
      begin
        write_lock = File.open("#{temp_path(file)}.lock", File::RDWR|File::CREAT, 0644)
        write_lock.flock(File::LOCK_EX)
        yield
      ensure
        write_lock.close
        File.unlink("#{temp_path(file)}.lock") if File.exists?("#{temp_path(file)}.lock")
      end
    end

    def temp_path(file)
      full_path = File.expand_path(File.join(@temp_path, file))
      raise Vagrancy::InvalidFilePath.new "access denied for path #{file}" unless Pathname.new(full_path).fnmatch? File.join(@temp_path, '**')
      full_path
    end

  end
end
