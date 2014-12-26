module hdf5.file;

import hdf5.id;
import hdf5.api;
import hdf5.exception;
import hdf5.library;

public import hdf5.id;
public import hdf5.plist;
public import hdf5.container;

import std.string    : toStringz;

version (unittest) {
    import std.file      : tempDir, remove, exists, setAttributes;
    import std.path      : buildPath;
    import std.stdio     : File;
    import std.exception : assertThrown;
}

public final class H5File : H5Container {
    package this(hid_t id) { super(id); }

    public {
        static alias open = openH5File;

        this(in string filename, in string mode = null, size_t userblock = 0) {
            auto fapl = new H5FileAccessPL;
            this(filename, mode, userblock, fapl);
        }
    }

    protected override void doClose() {
        auto files = findObjects(m_id, H5F_OBJ_FILE);
        auto objects = findObjects(m_id, H5F_OBJ_ALL & ~H5F_OBJ_FILE);
        foreach (ref file; files)
            while (file.valid)
                file.decref();
        foreach (ref object; objects)
            while (object.valid)
                object.decref();
        D_H5Fclose(m_id);
        destroy(files);
        destroy(objects);
    }

    protected final override void afterClose() {
        typeof(this).invalidateRegistry();
    }

    public final const @property {
        // Returns the userblock size in bytes.
        size_t userblock() {
            return this.fcpl.userblock;
        }

        /// Returns the string name of the current file driver.
        string driver() {
            return this.fapl.driver;
        }

        /// Returns the free space in the file in bytes.
        size_t freeSpace() {
            return D_H5Fget_freespace(m_id);
        }

        /// Returns the file size in bytes.
        size_t fileSize() {
            hsize_t size;
            D_H5Fget_filesize(m_id, &size);
            return size;
        }

        /// Determines the file's write intent, either "r" or "r+".
        string mode() {
            uint mode;
            D_H5Fget_intent(m_id, &mode);
            return mode == H5F_ACC_RDONLY ? "r" : "r+";
        }
    }

    private this(in string filename, in string mode, size_t userblock, in H5FileAccessPL fapl) {
        auto fcpl = new H5FileCreatePL;
        enforceH5((userblock == 0) || (mode != "r" && mode != "r+"),
                  "cannot specify userblock when reading a file");
        fcpl.userblock = userblock;

        auto open = (uint flags) => D_H5Fopen(filename.toStringz, flags, fapl.id);
        auto create = (uint flags) => D_H5Fcreate(filename.toStringz, flags, fcpl.id, fapl.id);

        hid_t file_id = H5I_INVALID_HID;
        if (mode == "r")
            file_id = open(H5F_ACC_RDONLY);
        else if (mode == "r+")
            file_id = open(H5F_ACC_RDWR);
        else if (mode == "w-" || mode == "x")
            file_id = create(H5F_ACC_EXCL);
        else if (mode == "w")
            file_id = create(H5F_ACC_TRUNC);
        else if (mode == "a")
            try
                file_id = open(H5F_ACC_RDWR);
            catch (H5Exception)
                file_id = create(H5F_ACC_EXCL);
        else if (mode is null)
            try
                file_id = open(H5F_ACC_RDWR);
            catch (H5Exception)
                try
                    file_id = open(H5F_ACC_RDONLY);
                catch (H5Exception)
                    file_id = create(H5F_ACC_EXCL);
        else
            throwH5(q{invalid mode: "%s" (expected r|r+|w|w-|x|a)}, mode);

        this(file_id);
        scope(failure) this.close();
        enforceH5(this.valid, "the opened file has a broken handle");
        enforceH5(userblock == this.userblock, "expected userblock %d, got %d",
                  userblock, this.userblock);
    }
}

public {
    bool isHDF5(string filename) {
        return D_H5Fis_hdf5(filename.toStringz) > 0;
    }

    // TODO: add support for log, family, multi, split (mpio?) (windows?)

    H5File openH5File
    (in string filename, in string mode = null, size_t userblock = 0)
    out (file) {
        assert(file.valid && file.driver == "sec2");
    }
    body {
        return new H5File(filename, mode, userblock);
    }

    H5File openH5File(string driver : "stdio")
    (in string filename, in string mode = null, size_t userblock = 0)
    out (file) {
        assert(file.valid && file.driver == "stdio");
    }
    body {
        auto fapl = new H5FileAccessPL;
        fapl.setDriver!"stdio";
        return new H5File(filename, mode, userblock, fapl);
    }

    H5File openH5File(string driver : "sec2")
    (in string filename, in string mode = null, size_t userblock = 0)
    out (file) {
        assert(file.valid && file.driver == "sec2");
    }
    body {
        auto fapl = new H5FileAccessPL;
        fapl.setDriver!"sec2";
        return new H5File(filename, mode, userblock, fapl);
    }

    H5File openH5File(string driver : "core", bool filebacked = CORE_DRIVER_FILEBACKED,
                      size_t increment = CORE_DRIVER_INCREMENT)
    (in string filename, in string mode = null, size_t userblock = 0)
    out (file) {
        assert(file.valid && file.driver == "core");
    }
    body {
        // TODO: add support for core images
        auto fapl = new H5FileAccessPL;
        fapl.setDriver!"core"(filebacked, increment);
        return new H5File(filename, mode, userblock, fapl);
    }
}

// file opening modes
unittest {
    auto filename = tempDir.buildPath("foo.h5");
    scope(exit) filename.remove();
    auto mkfile = (string mode = null, size_t userblock = 0) =>
                  new H5File(filename, mode, userblock);

    // bad input arguments
    assertThrown!H5Exception(new H5File(filename, "foo"));
    assertThrown!H5Exception(new H5File(null));
    assertThrown!H5Exception(new H5File("/foo/bar/baz"));

    // no existing file
    auto file = mkfile();
    scope(exit) file.close();
    assert(file.mode == "r+");
    file.close();
    assert(filename.isHDF5);

    // read-only file
    filename.setAttributes(0x0100);
    file = mkfile();
    assert(file.mode == "r");
    file.close();
    filename.remove();

    // existing non-HDF5 file
    auto f = File(filename, "w");
    f.write("foo");
    f.close();
    assertThrown!H5Exception(mkfile());
    assert(!filename.isHDF5);

    // "w" means overwrite
    file = mkfile("w", 1024);
    file.createGroup("bar");
    file.group("bar");
    file.close();
    file = mkfile("w");
    assertThrown!H5Exception(file.group("bar"));
    file.close();

    // "w-"/"x" means exclusive
    filename.remove();
    mkfile("w-").close();
    assertThrown!H5Exception(mkfile("w-"));
    filename.remove();
    mkfile("x").close();
    assertThrown!H5Exception(mkfile("x"));

    // "a" means append
    file = mkfile("a");
    file.createGroup("bar");
    file.group("bar");
    file.close();
    file = mkfile("a");
    file.group("bar");
    file.close();
}

unittest {
    auto filename = tempDir.buildPath("foo.h5");
    scope(exit) filename.remove();

    auto file = new H5File(filename);
    scope(exit) file.close();
    assert(filename.exists);
    assert(file.driver == "sec2");
    assert(file.filename == filename);
    assert(file.name == "/");
    assert(file.userblock == 0);
}
