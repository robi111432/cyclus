"""Python wrapper for cyclus."""
from __future__ import division, unicode_literals, print_function

# Cython imports
from libcpp.utility cimport pair as std_pair
from libcpp.set cimport set as std_set
from libcpp.map cimport map as std_map
from libcpp.vector cimport vector as std_vector
from libcpp.string cimport string as std_string
from cython.operator cimport dereference as deref
from cython.operator cimport preincrement as inc
from libc.stdlib cimport malloc, free
from libc.string cimport memcpy
from libcpp cimport bool as cpp_bool

from binascii import hexlify
import uuid

cimport numpy as np
import numpy as np
import pandas as pd

# local imports

from cyclus cimport cpp_jsoncpp
from cyclus cimport jsoncpp
from cyclus import jsoncpp

from cyclus cimport cpp_cyclus
from cyclus cimport cpp_typesystem
from cyclus.cpp_stringstream cimport stringstream
from cyclus.typesystem cimport py_to_any, db_to_py, uuid_cpp_to_py, \
    str_py_to_cpp, std_string_to_py, std_vector_std_string_to_py, \
    bool_to_py, int_to_py, std_set_std_string_to_py


# startup numpy
np.import_array()
np.import_ufunc()


cdef class _Datum:

    def __cinit__(self):
        """Constructor for Datum type conversion."""
        self._free = False
        self.ptx = NULL

    def __dealloc__(self):
        """Datum destructor."""
        if self.ptx == NULL:
            return
        cdef cpp_cyclus.Datum* cpp_ptx
        if self._free:
            cpp_ptx = <cpp_cyclus.Datum*> self.ptx
            del cpp_ptx
            self.ptx = NULL

    def add_val(self, const char* field, value, shape=None, dbtype=cpp_typesystem.BLOB):
        """Adds Datum value to current record as the corresponding cyclus data type.

        Parameters
        ----------
        field : pointer to char/str
            The column name.
        value : object
            Value in table column.
        shape : list or tuple of ints
            Length of value.
        dbtype : cpp data type
            Data type as defined by cyclus typesystem

        Returns
        -------
        self : Datum
        """
        cdef int i, n
        cdef std_vector[int] cpp_shape
        cdef cpp_cyclus.hold_any v = py_to_any(value, dbtype)
        cdef std_string cfield
        if shape is None:
            (<cpp_cyclus.Datum*> self.ptx).AddVal(field, v)
        else:
            n = len(shape)
            cpp_shape.resize(n)
            for i in range(n):
                cpp_shape[i] = <int> shape[i]
            (<cpp_cyclus.Datum*> self.ptx).AddVal(field, v, &cpp_shape)
        return self

    def record(self):
        """Records the Datum."""
        (<cpp_cyclus.Datum*> self.ptx).Record()

    property title:
        """The datum name."""
        def __get__(self):
            s = (<cpp_cyclus.Datum*> self.ptx).title()
            return s


class Datum(_Datum):
    """Datum class."""


cdef class _FullBackend:

    def __cinit__(self):
        """Full backend C++ constructor"""
        self._tables = None

    def __dealloc__(self):
        """Full backend C++ destructor."""
        # Note that we have to do it this way since self.ptx is void*
        if self.ptx == NULL:
            return
        cdef cpp_cyclus.FullBackend * cpp_ptx = <cpp_cyclus.FullBackend *> self.ptx
        del cpp_ptx
        self.ptx = NULL

    def query(self, table, conds=None):
        """Queries a database table.

        Parameters
        ----------
        table : str
            The table name.
        conds : iterable, optional
            A list of conditions.

        Returns
        -------
        results : pd.DataFrame
            Pandas DataFrame the represents the table
        """
        cdef int i, j
        cdef int nrows, ncols
        cdef std_string tab = str(table).encode()
        cdef std_string field
        cdef cpp_cyclus.QueryResult qr
        cdef std_vector[cpp_cyclus.Cond] cpp_conds
        cdef std_vector[cpp_cyclus.Cond]* conds_ptx
        cdef std_map[std_string, cpp_cyclus.DbTypes] coltypes
        # set up the conditions
        if conds is None:
            conds_ptx = NULL
        else:
            coltypes = (<cpp_cyclus.FullBackend*> self.ptx).ColumnTypes(tab)
            for cond in conds:
                cond0 = cond[0].encode()
                cond1 = cond[1].encode()
                field = std_string(<const char*> cond0)
                if coltypes.count(field) == 0:
                    continue  # skips non-existent columns
                cpp_conds.push_back(cpp_cyclus.Cond(field, cond1,
                    py_to_any(cond[2], coltypes[field])))
            if cpp_conds.size() == 0:
                conds_ptx = NULL
            else:
                conds_ptx = &cpp_conds
        # query, convert, and return
        qr = (<cpp_cyclus.FullBackend*> self.ptx).Query(tab, conds_ptx)
        nrows = qr.rows.size()
        ncols = qr.fields.size()
        cdef dict res = {}
        cdef list fields = []
        for j in range(ncols):
            res[j] = []
            f = qr.fields[j]
            fields.append(f.decode())
        for i in range(nrows):
            for j in range(ncols):
                res[j].append(db_to_py(qr.rows[i][j], qr.types[j]))
        res = {fields[j]: v for j, v in res.items()}
        results = pd.DataFrame(res, columns=fields)
        return results

    property tables:
        """Retrieves the set of tables present in the database."""
        def __get__(self):
            if self._tables is not None:
                return self._tables
            cdef std_set[std_string] ctabs = \
                (<cpp_cyclus.FullBackend*> self.ptx).Tables()
            cdef std_set[std_string].iterator it = ctabs.begin()
            cdef set tabs = set()
            while it != ctabs.end():
                tab = deref(it)
                tabs.add(tab.decode())
                inc(it)
            self._tables = tabs
            return self._tables

        def __set__(self, value):
            self._tables = value


class FullBackend(_FullBackend, object):
    """Full backend cyclus database interface."""

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        self.close()


cdef class _SqliteBack(_FullBackend):

    def __cinit__(self, path):
        """Full backend C++ constructor"""
        cdef std_string cpp_path = str(path).encode()
        self.ptx = new cpp_cyclus.SqliteBack(cpp_path)

    def __dealloc__(self):
        """Full backend C++ destructor."""
        # Note that we have to do it this way since self.ptx is void*
        if self.ptx == NULL:
            return
        cdef cpp_cyclus.SqliteBack * cpp_ptx = <cpp_cyclus.SqliteBack *> self.ptx
        del cpp_ptx
        self.ptx = NULL

    def flush(self):
        """Flushes the database to disk."""
        (<cpp_cyclus.SqliteBack*> self.ptx).Flush()

    def close(self):
        """Closes the backend, flushing it in the process."""
        self.flush()  # just in case
        (<cpp_cyclus.SqliteBack*> self.ptx).Close()

    property name:
        """The name of the database."""
        def __get__(self):
            name = (<cpp_cyclus.SqliteBack*> self.ptx).Name()
            name = name.decode()
            return name


class SqliteBack(_SqliteBack, FullBackend):
    """SQLite backend cyclus database interface."""


cdef class _Hdf5Back(_FullBackend):

    def __cinit__(self, path):
        """Hdf5 backend C++ constructor"""
        cdef std_string cpp_path = str(path).encode()
        self.ptx = new cpp_cyclus.Hdf5Back(cpp_path)

    def __dealloc__(self):
        """Full backend C++ destructor."""
        # Note that we have to do it this way since self.ptx is void*
        if self.ptx == NULL:
            return
        cdef cpp_cyclus.Hdf5Back * cpp_ptx = <cpp_cyclus.Hdf5Back *> self.ptx
        del cpp_ptx
        self.ptx = NULL

    def flush(self):
        """Flushes the database to disk."""
        (<cpp_cyclus.Hdf5Back*> self.ptx).Flush()

    def close(self):
        """Closes the backend, flushing it in the process."""
        (<cpp_cyclus.Hdf5Back*> self.ptx).Close()

    property name:
        """The name of the database."""
        def __get__(self):
            name = (<cpp_cyclus.Hdf5Back*> self.ptx).Name()
            name = name.decode()
            return name


class Hdf5Back(_Hdf5Back, FullBackend):
    """HDF5 backend cyclus database interface."""


cdef class _Recorder:

    def __cinit__(self, bint inject_sim_id=True):
        """Recorder C++ constructor"""
        self.ptx = new cpp_cyclus.Recorder(<cpp_bool> inject_sim_id)

    def __dealloc__(self):
        """Recorder C++ destructor."""
        if self.ptx == NULL:
            return
        self.close()
        # Note that we have to do it this way since self.ptx is void*
        cdef cpp_cyclus.Recorder * cpp_ptx = <cpp_cyclus.Recorder *> self.ptx
        del cpp_ptx
        self.ptx = NULL

    property dump_count:
        """The frequency of recording."""
        def __get__(self):
            return (<cpp_cyclus.Recorder*> self.ptx).dump_count()

        def __set__(self, value):
            (<cpp_cyclus.Recorder*> self.ptx).set_dump_count(<unsigned int> value)

    property sim_id:
        """The simulation id of the recorder."""
        def __get__(self):
            return uuid_cpp_to_py((<cpp_cyclus.Recorder*> self.ptx).sim_id())

    property inject_sim_id:
        """Whether or not to inject the simulation id into the tables."""
        def __get__(self):
            return (<cpp_cyclus.Recorder*> self.ptx).inject_sim_id()

        def __set__(self, value):
            (<cpp_cyclus.Recorder*> self.ptx).inject_sim_id(<bint> value)

    def new_datum(self, title):
        """Registers a backend with the recorder."""
        cdef std_string cpp_title = str_py_to_cpp(title)
        cdef _Datum d = Datum(new=False)
        (<_Datum> d).ptx = (<cpp_cyclus.Recorder*> self.ptx).NewDatum(cpp_title)
        return d

    def register_backend(self, backend):
        """Registers a backend with the recorder."""
        cdef cpp_cyclus.RecBackend* b
        if isinstance(backend, Hdf5Back):
            b = <cpp_cyclus.RecBackend*> (
                <cpp_cyclus.Hdf5Back*> (<_Hdf5Back> backend).ptx)
        elif isinstance(backend, SqliteBack):
            b = <cpp_cyclus.RecBackend*> (
                <cpp_cyclus.SqliteBack*> (<_SqliteBack> backend).ptx)
        (<cpp_cyclus.Recorder*> self.ptx).RegisterBackend(b)

    def flush(self):
        """Flushes the recorder to disk."""
        (<cpp_cyclus.Recorder*> self.ptx).Flush()

    def close(self):
        """Closes the recorder."""
        (<cpp_cyclus.Recorder*> self.ptx).Close()


class Recorder(_Recorder, object):
    """Cyclus recorder interface."""

#
# Agent Spec
#
cdef class _AgentSpec:

    def __cinit__(self, spec=None, lib=None, agent=None, alias=None):
        cdef std_string cpp_spec, cpp_lib, cpp_agent, cpp_alias
        if spec is None:
            self.ptx = new cpp_cyclus.AgentSpec()
        elif lib is None:
            cpp_spec = str_py_to_cpp(spec)
            self.ptx = new cpp_cyclus.AgentSpec(cpp_spec)
        else:
            cpp_spec = str_py_to_cpp(spec)
            cpp_lib = str_py_to_cpp(lib)
            cpp_agent = str_py_to_cpp(agent)
            cpp_alias = str_py_to_cpp(alias)
            self.ptx = new cpp_cyclus.AgentSpec(cpp_spec, cpp_lib,
                                                cpp_agent, cpp_alias)

    def __dealloc__(self):
        del self.ptx

    def __str__(self):
        cdef std_string cpp_rtn = self.ptx.str()
        rtn = std_string_to_py(cpp_rtn)
        return rtn

    def sanatize(self):
        cdef std_string cpp_rtn = self.ptx.Sanitize()
        rtn = std_string_to_py(cpp_rtn)
        return rtn

    @property
    def path(self):
        cdef std_string cpp_rtn = self.ptx.path()
        rtn = std_string_to_py(cpp_rtn)
        return rtn

    @property
    def lib(self):
        cdef std_string cpp_rtn = self.ptx.lib()
        rtn = std_string_to_py(cpp_rtn)
        return rtn

    @property
    def agent(self):
        cdef std_string cpp_rtn = self.ptx.agent()
        rtn = std_string_to_py(cpp_rtn)
        return rtn

    @property
    def alias(self):
        cdef std_string cpp_rtn = self.ptx.alias()
        rtn = std_string_to_py(cpp_rtn)
        return rtn


class AgentSpec(_AgentSpec):
    """AgentSpec C++ wrapper

    Parameters
    ----------
    spec : str or None, optional
        This repesents either the full string form of the spec or
        just the path.
    lib : str or None, optional
    agent : str or None, optional
    alias : str or None, optional
    """

#
# Dynamic Module
#
cdef class _DynamicModule:

    def __cinit__(self):
        self.ptx = new cpp_cyclus.DynamicModule()

    def __dealloc__(self):
        del self.ptx

    @staticmethod
    def make(ctx, spec):
        """Returns a newly constructed agent for the given module spec.

        Paramters
        ---------
        ctx : Context
        spec : AgentSpec or str

        Returns
        -------
        rtn : Agent
        """
        cdef _Agent agent = Agent()
        cdef _AgentSpec cpp_spec
        if isinstance(spec, str):
            spec = AgentSpec(spec)
        cpp_spec = <_AgentSpec> spec
        agent.ptx = cpp_cyclus.DynamicModule.Make(
            (<_Context> ctx).ptx,
            deref(cpp_spec.ptx),
            )
        return agent

    def exists(self, _AgentSpec spec):
        """Tests whether an agent spec exists."""
        cdef cpp_bool rtn = self.ptx.Exists(deref(spec.ptx))
        return rtn

    def close_all(self):
        """Closes all dynamic modules."""
        self.ptx.CloseAll()

    @property
    def path(self):
        cdef std_string cpp_rtn = self.ptx.path()
        rtn = std_string_to_py(cpp_rtn)
        return rtn


class DynamicModule(_DynamicModule):
    """Dynamic Module wrapper class."""


#
# Env
#
cdef class _Env:

    @staticmethod
    def path_base(path):
        """Effectively basename"""
        cdef std_string cpp_path = str_py_to_cpp(path)
        cdef std_string cpp_rtn = cpp_cyclus.Env.PathBase(cpp_path)
        rtn = std_string_to_py(cpp_rtn)
        return rtn

    @property
    def install_path(self):
        """The Cyclus install path."""
        cdef std_string cpp_rtn = cpp_cyclus.Env.GetInstallPath()
        rtn = std_string_to_py(cpp_rtn)
        return rtn

    @property
    def build_path(self):
        """The Cyclus build path."""
        cdef std_string cpp_rtn = cpp_cyclus.Env.GetBuildPath()
        rtn = std_string_to_py(cpp_rtn)
        return rtn

    @staticmethod
    def get(var):
        """Obtains an environment variable."""
        cdef std_string cpp_var = str_py_to_cpp(var)
        cdef std_string cpp_rtn = cpp_cyclus.Env.GetEnv(cpp_var)
        rtn = std_string_to_py(cpp_rtn)
        return rtn

    @property
    def nuc_data(self):
        """The nuc_data path."""
        cdef std_string cpp_rtn = cpp_cyclus.Env.nuc_data()
        rtn = std_string_to_py(cpp_rtn)
        return rtn

    @staticmethod
    def set_nuc_data_path(path=None):
        """Initializes the path to the cyclus_nuc_data.h5 file

        By default, it is assumed to be located in the path given by
        GetInstallPath()/share; however, paths in environment variable
        CYCLUS_NUC_DATA are checked first.
        """
        cdef std_string cpp_path
        if path is None:
            cpp_cyclus.Env.SetNucDataPath(cpp_cyclus.Env.nuc_data())
        else:
            cpp_path = str_py_to_cpp(path)
            cpp_cyclus.Env.SetNucDataPath(cpp_path)

    @staticmethod
    def rng_schema(flat=False):
        """Returns the current rng schema.  Uses CYCLUS_RNG_SCHEMA env var
        if set; otherwise uses the default install location. If using the
        default ocation, set flat=True for the default flat schema.
        """
        cdef std_string cpp_rtn = cpp_cyclus.Env.rng_schema(flat)
        rtn = std_string_to_py(cpp_rtn)
        return rtn

    @property
    def cyclus_path(self):
        """A tuple of strings representing where cyclus searches for
        modules.
        """
        cdef std_vector[std_string] cpp_rtn = cpp_cyclus.Env.cyclus_path()
        rtn = std_vector_std_string_to_py(cpp_rtn)
        return tuple(rtn)

    @property
    def allow_milps(self):
        """whether or not Cyclus should allow Mixed-Integer Linear Programs
        The default depends on a compile time option DEFAULT_ALLOW_MILPS, but
        may be specified at run time with the ALLOW_MILPS environment variable.
        """
        cdef cpp_bool cpp_rtn = cpp_cyclus.Env.allow_milps()
        rtn = bool_to_py(cpp_rtn)
        return rtn

    @property
    def env_delimiter(self):
        """the correct environment variable delimiter based on the file
        system.
        """
        cdef std_string cpp_rtn = cpp_cyclus.Env.EnvDelimiter()
        rtn = std_string_to_py(cpp_rtn)
        return rtn

    @property
    def path_delimiter(self):
        """the correct path delimiter based on the file
        system.
        """
        cdef std_string cpp_rtn = cpp_cyclus.Env.PathDelimiter()
        rtn = std_string_to_py(cpp_rtn)
        return rtn

    @staticmethod
    def find_module(path):
        """Returns the full path to a module by searching through default
        install and CYCLUS_PATH directories.
        """
        cdef std_string cpp_path = str_py_to_cpp(path)
        cdef std_string cpp_rtn = cpp_cyclus.Env.FindModule(cpp_path)
        rtn = std_string_to_py(cpp_rtn)
        return rtn


class Env(_Env):
    """Environment wrapper class.

    An environment utility to help locate files and find environment
    settings. The environment for a given simulation can be accessed via the
    simulation's Context.
    """


#
# Logger
#

# LogLevel
LEV_ERROR = cpp_cyclus.LEV_ERROR
LEV_WARN = cpp_cyclus.LEV_WARN
LEV_INFO1 = cpp_cyclus.LEV_INFO1
LEV_INFO2 = cpp_cyclus.LEV_INFO2
LEV_INFO3 = cpp_cyclus.LEV_INFO3
LEV_INFO4 = cpp_cyclus.LEV_INFO4
LEV_INFO5 = cpp_cyclus.LEV_INFO5
LEV_DEBUG1 = cpp_cyclus.LEV_INFO5
LEV_DEBUG2 = cpp_cyclus.LEV_DEBUG2
LEV_DEBUG3 = cpp_cyclus.LEV_DEBUG3
LEV_DEBUG4 = cpp_cyclus.LEV_DEBUG4
LEV_DEBUG5 = cpp_cyclus.LEV_DEBUG5


cdef class _Logger:

    @property
    def report_level(self):
        """Use to get/set the (global) log level report cutoff."""
        cdef cpp_cyclus.LogLevel cpp_rtn = cpp_cyclus.Logger.ReportLevel()
        rtn = int_to_py(cpp_rtn)
        return rtn

    @report_level.setter
    def report_level(self, int level):
        cpp_cyclus.Logger.SetReportLevel(<cpp_cyclus.LogLevel> level)

    @property
    def no_agent(self):
        """Set whether or not agent/agent log entries should be printed"""
        cdef cpp_bool cpp_rtn = cpp_cyclus.Logger.NoAgent()
        rtn = bool_to_py(cpp_rtn)
        return rtn

    @no_agent.setter
    def no_agent(self, bint na):
        cpp_cyclus.Logger.SetNoAgent(na)

    @property
    def no_mem(self):
        cdef cpp_bool cpp_rtn = cpp_cyclus.Logger.NoMem()
        rtn = bool_to_py(cpp_rtn)
        return rtn

    @no_mem.setter
    def no_mem(self, bint nm):
        cpp_cyclus.Logger.SetNoMem(nm)

    @staticmethod
    def to_log_level(text):
        """Converts a string into a corresponding LogLevel value.

        For strings that do not correspond to any particular LogLevel enum value
        the method returns the LogLevel value `LEV_ERROR`.  This method is
        primarily intended for translating command line verbosity argument(s) in
        appropriate report levels.  LOG(level) statements
        """
        cdef std_string cpp_text = str_py_to_cpp(text)
        cdef cpp_cyclus.LogLevel cpp_rtn = cpp_cyclus.Logger.ToLogLevel(cpp_text)
        rtn = <int> cpp_rtn
        return rtn

    @staticmethod
    def to_string(level):
        """Converts a LogLevel enum value into a corrsponding string.

        For a level argments that have no corresponding string value, the string
        `BAD_LEVEL` is returned.  This method is primarily intended for translating
        LOG(level) statement levels into appropriate strings for output to stdout.
        """
        cdef cpp_cyclus.LogLevel cpp_level = <cpp_cyclus.LogLevel> level
        cdef std_string cpp_rtn = cpp_cyclus.Logger.ToString(cpp_level)
        rtn = std_string_to_py(cpp_rtn)
        return rtn


class Logger(_Logger):
    """A logging tool providing finer grained control over standard output
    for debugging and other purposes.
    """

#
# Errors
#
def get_warn_limit():
    """Returns the current warning limit."""
    wl = cpp_cyclus.warn_limit
    return wl


def set_warn_limit(unsigned int wl):
    """Sets the warning limit."""
    cpp_cyclus.warn_limit = wl


def get_warn_as_error():
    """Returns the current value for wether warnings should be treated
    as errors.
    """
    wae = bool_to_py(cpp_cyclus.warn_as_error)
    return wae


def set_warn_as_error(bint wae):
    """Sets whether warnings should be treated as errors."""
    cpp_cyclus.warn_as_error = wae


#
# PyHooks
#
def py_init_hooks():
    """Initializes Cyclus-internal Python hooks. This is called
    automatically when cyclus is imported. Users should not need to call
    this function.
    """
    cpp_cyclus.PyInitHooks()

#
# XML
#
cdef class _XMLFileLoader:

    def __cinit__(self, recorder, backend, schema_file, input_file=""):
        cdef std_string cpp_schema_file = str_py_to_cpp(schema_file)
        cdef std_string cpp_input_file = str_py_to_cpp(input_file)
        self.ptx = new cpp_cyclus.XMLFileLoader(
            <cpp_cyclus.Recorder *> (<_Recorder> recorder).ptx,
            <cpp_cyclus.QueryableBackend *> (<_FullBackend> backend).ptx,
            cpp_schema_file, cpp_input_file)

    def __dealloc__(self):
        del self.ptx

    def load_sim(self):
        """Load an entire simulation from the inputfile."""
        self.ptx.LoadSim()


class XMLFileLoader(_XMLFileLoader):
    """Handles initialization of a database with information from
    a cyclus xml input file.

    Create a new loader reading from the xml simulation input file and writing
    to and initializing the backends in the recorder. The recorder must
    already have the backend registered. schema_file identifies the master
    xml rng schema used to validate the input file.
    """


cdef class _XMLFlatLoader:

    def __cinit__(self, recorder, backend, schema_file, input_file=""):
        cdef std_string cpp_schema_file = str_py_to_cpp(schema_file)
        cdef std_string cpp_input_file = str_py_to_cpp(input_file)
        self.ptx = new cpp_cyclus.XMLFlatLoader(
            <cpp_cyclus.Recorder *> (<_Recorder> recorder).ptx,
            <cpp_cyclus.QueryableBackend *> (<_FullBackend> backend).ptx,
            cpp_schema_file, cpp_input_file)

    def __dealloc__(self):
        del self.ptx

    def load_sim(self):
        """Load an entire simulation from the inputfile."""
        self.ptx.LoadSim()


class XMLFlatLoader(_XMLFlatLoader):
    """Handles initialization of a database with information from
    a cyclus xml input file.

    Create a new loader reading from the xml simulation input file and writing
    to and initializing the backends in the recorder. The recorder must
    already have the backend registered. schema_file identifies the master
    xml rng schema used to validate the input file.

    Notes
    -----
    This is not a subclass of the XMLFileLoader Python bindings, even
    though the C++ class is a subclass in C++. Rather, they are duck
    typed by exposing the same interface. This makes handling the
    instance pointers in Cython a little easier.
    """


def load_string_from_file(filename):
    """Loads an XML file from a path."""
    cdef std_string cpp_filename = str_py_to_cpp(filename)
    cdef std_string cpp_rtn = cpp_cyclus.LoadStringFromFile(cpp_filename)
    rtn = std_string_to_py(cpp_rtn)
    return rtn



cdef class _XMLParser:

    def __cinit__(self, filename=None, raw=None):
        cdef std_string s, inp
        self.ptx = new cpp_cyclus.XMLParser()
        if filename is not None:
            s = str_py_to_cpp(filename)
            inp = cpp_cyclus.LoadStringFromFile(s)
        elif raw is not None:
            inp = str_py_to_cpp(raw)
        else:
            raise RuntimeError("Either a filename or a raw XML string "
                               "must be provided to XMLParser")
        self.ptx.Init(inp)

    def __dealloc__(self):
        del self.ptx


class XMLParser(_XMLParser):
    """A helper class to hold xml file data and provide automatic
    validation.

    Parameters
    ----------
    filename : str, optional
        Path to file to load.
    raw : str, optional
        XML string to load.
    """


cdef class _InfileTree:

    def __cinit__(self, _XMLParser parser):
        self.ptx = new cpp_cyclus.InfileTree(parser.ptx[0])

    def __dealloc__(self):
        del self.ptx

    def optional_query(self, query, default):
        """A query method for optional parameters.

        Parameters
        ----------
        query : str
            The XML path to test if it exists.
        default : any type
            The default value to return if the XML path does not exist in
            the tree. The type of the return value (str, bool, int, etc)
            is determined by the type of the default.
        """
        cdef std_string cpp_query = str_py_to_cpp(query)
        cdef std_string str_default, str_rtn
        if isinstance(default, str):
            str_default = str_py_to_cpp(default)
            str_rtn = cpp_cyclus.OptionalQuery[std_string](self.ptx, cpp_query,
                                                           str_default)
            rtn = std_string_to_py(str_rtn)
        else:
            raise TypeError("Type of default value not recognized, only "
                            "str is currently supported.")
        return rtn


class InfileTree(_InfileTree):
    """A class for extracting information from a given XML parser

    Parameters
    ----------
    parser : XMLParser
        An XMLParser instance.
    """

#
# Simulation Managment
#

cdef class _Timer:

    def __cinit__(self, bint init=True):
        self._free = init
        if init:
            self.ptx = new cpp_cyclus.Timer()
        else:
            self.ptx == NULL

    def __dealloc__(self):
        if self.ptx == NULL:
            return
        elif self._free:
            del self.ptx

    def run_sim(self):
        """Runs the simulation."""
        self.ptx.RunSim()


class Timer(_Timer):
    """Controls simulation timestepping and inter-timestep phases.

    Parameters
    ----------
    init : bool, optional
        Whether or not we should initialize a new C++ Timer instance.
    """


cdef class _SimInit:

    def __cinit__(self, recorder, backend):
        self.ptx = new cpp_cyclus.SimInit()
        self.ptx.Init(
            <cpp_cyclus.Recorder *> (<_Recorder> recorder).ptx,
            <cpp_cyclus.QueryableBackend *> (<_FullBackend> backend).ptx,
            )
        self._timer = None

    def __dealloc__(self):
        del self.ptx

    @property
    def timer(self):
        """Returns the initialized timer. Note that either Init, Restart,
        or Branch must be called first.
        """
        if self._timer is None:
            self._timer = Timer(init=False)
            (<_Timer> self._timer).ptx = self.ptx.timer()
        return self._timer


class SimInit(_SimInit):
    """Handles initialization of a simulation from the output database. After
    calling Init, Restart, or Branch, the initialized Context, Timer, and
    Recorder can be retrieved.

    Parameters
    ----------
    recorder : Recorder
        The recorder class for the simulation.
    backend : QueryableBackend
        A backend to use for this simulation.
    """

#
# Agent
#
cdef class _Agent:

    def __cinit__(self, bint free=False):
        self._free = free
        self.ptx == NULL
        self._annotations = None

    def __dealloc__(self):
        cdef cpp_cyclus.Agent* cpp_ptx
        if self.ptx == NULL:
            return
        elif self._free:
            cpp_ptx = <cpp_cyclus.Agent*> self.ptx
            del cpp_ptx

    @property
    def schema(self):
        """An agent's xml rng schema for initializing from input files. All
        concrete agents should override this function. This must validate the same
        xml input that the InfileToDb function receives.
        """
        cdef std_string cpp_rtn = (<cpp_cyclus.Agent*> self.ptx).schema()
        rtn = std_string_to_py(cpp_rtn)
        return rtn

    @property
    def version(self):
        """Agent version string."""
        cdef std_string cpp_rtn = (<cpp_cyclus.Agent*> self.ptx).version()
        rtn = std_string_to_py(cpp_rtn)
        return rtn

    @property
    def annotations(self):
        """Agent annotations."""
        cdef jsoncpp.Value cpp_rtn = jsoncpp.Value()
        if self._annotations is None:
            cpp_rtn._inst[0] = (<cpp_cyclus.Agent*> self.ptx).annotations()
        self._annotations = cpp_rtn
        return self._annotations


class Agent(_Agent):
    """The abstract base class used by all types of agents
    that live and interact in a simulation.
    """


#
# Version Info
#

def describe_version():
    """Describes the Cyclus version."""
    rtn = cpp_cyclus.describe()
    rtn = rtn.decode()
    return rtn


def core_version():
    """Cyclus core version."""
    rtn = cpp_cyclus.core()
    rtn = rtn.decode()
    return rtn


def boost_version():
    """Boost version."""
    rtn = cpp_cyclus.boost()
    rtn = rtn.decode()
    return rtn


def sqlite3_version():
    """SQLite3 version."""
    rtn = cpp_cyclus.sqlite3()
    rtn = rtn.decode()
    return rtn


def hdf5_version():
    """HDF5 version."""
    rtn = cpp_cyclus.hdf5()
    rtn = rtn.decode()
    return rtn


def xml2_version():
    """libxml 2 version."""
    rtn = cpp_cyclus.xml2()
    rtn = rtn.decode()
    return rtn


def xmlpp_version():
    """libxml++ version."""
    rtn = cpp_cyclus.xmlpp()
    rtn = rtn.decode()
    return rtn


def coincbc_version():
    """Coin CBC version."""
    rtn = cpp_cyclus.coincbc()
    rtn = rtn.decode()
    return rtn


def coinclp_version():
    """Coin CLP version."""
    rtn = cpp_cyclus.coinclp()
    rtn = rtn.decode()
    return rtn


def version():
    """Returns string of the cyclus version and its dependencies."""
    s = "Cyclus Core " + core_version() + " (" + describe_version() + ")\n\n"
    s += "Dependencies:\n"
    s += "   Boost    " + boost_version() + "\n"
    s += "   Coin-Cbc " + coincbc_version() + "\n"
    s += "   Coin-Clp " + coinclp_version() + "\n"
    s += "   Hdf5     " + hdf5_version() + "\n"
    s += "   Sqlite3  " + sqlite3_version() + "\n"
    s += "   xml2     " + xml2_version() + "\n"
    s += "   xml++    " + xmlpp_version() + "\n"
    return s

#
# Context
#
cdef class _Context:

    def __cinit__(self, timer, recorder):
        self.ptx = new cpp_cyclus.Context(
            (<_Timer> timer).ptx,
            (<cpp_cyclus.Recorder*> (<_Recorder> recorder).ptx),
            )

    def __dealloc__(self):
        del self.ptx

    def del_agent(self, agent):
        """Destructs and cleans up an agent (and it's children recursively)."""
        self.ptx.DelAgent(<cpp_cyclus.Agent*> (<_Agent> agent).ptx)


class Context(_Context):
    """A simulation context provides access to necessary simulation-global
    functions and state. All code that writes to the output database, needs to
    know simulation time, creates/builds facilities, and/or uses loaded
    composition recipes will need a context pointer. In general, all global
    state should be accessed through a simulation context.

    Parameters
    ----------
    timer : Timer
        An instance of the timer class.
    recorder : Recorder
        An instance of the recorder class.

    Warnings
    --------
    * The context takes ownership of and manages the lifetime/destruction
      of all agents constructed with it (including Cloned agents). Agents should
      generally NEVER be allocated on the stack.
    * The context takes ownership of the solver and will manage its
      destruction.
    """

#
# Discovery
#
def discover_specs(path, library):
    """Discover archetype specifications for a path and library.
    Returns a set of strings.
    """
    cdef std_string cpp_path = str_py_to_cpp(path)
    cdef std_string cpp_library = str_py_to_cpp(library)
    cdef std_set[std_string] cpp_rtn = cpp_cyclus.DiscoverSpecs(cpp_path,
                                                                cpp_library)
    rtn = std_set_std_string_to_py(cpp_rtn)
    return rtn


def discover_specs_in_cyclus_path():
    """Discover archetype specifications that live recursively in CYCLUS_PATH
    directories. Returns a set of strings.
    """
    cdef std_set[std_string] cpp_rtn = cpp_cyclus.DiscoverSpecsInCyclusPath()
    rtn = std_set_std_string_to_py(cpp_rtn)
    return rtn


def discover_metadata_in_cyclus_path():
    """Discover archetype metadata in cyclus path. Returns a Jason.Value
    object.
    """
    cdef jsoncpp.Value cpp_rtn = jsoncpp.Value()
    cpp_rtn._inst[0] = cpp_cyclus.DiscoverMetadataInCyclusPath()
    rtn = cpp_rtn
    return rtn
