# cython: c__stringype=str, c_string_encoding=utf8

from chat_trie cimport *
from cpython.version cimport PY_MAJOR_VERSION

cimport cpython
cimport cython

# TODO: Try this at compile-time?
assert sizeof(long) <= sizeof(value_t)
assert sizeof(double) <= sizeof(value_t)

cdef inline char* _asbytes(basestring key):
    if isinstance(key, unicode):
        return (<unicode> key).encode('UTF-8')
    else:
        return <bytes> key

cdef inline value_t* _tryget(hattrie_t* trie, basestring key):
    cdef ssize_t c_keylen = len(key)
    cdef char* c_key = _asbytes(key)
    cdef value_t* value_ptr
    value_ptr = hattrie_tryget(trie, c_key, c_keylen)
    return value_ptr

cdef inline _set(hattrie_t* trie, basestring key, value_t value):
    cdef ssize_t c_keylen = len(key)
    cdef char* c_key = _asbytes(key)
    hattrie_get(trie, c_key, c_keylen)[0] = value

cdef inline value_t _setdefault(hattrie_t* trie, basestring key, value_t value):
    cdef ssize_t c_keylen = len(key)
    cdef char* c_key = _asbytes(key)
    cdef value_t* value_ptr
    value_ptr = hattrie_tryget(trie, c_key, c_keylen)
    if value_ptr == NULL:
        hattrie_get(trie, c_key, c_keylen)[0] = value
    else:
        value = value_ptr[0]
    return value


cdef class BaseTrie


@cython.no_gc_clear
cdef class Iterable:

    cdef BaseTrie _parent
    cdef hattrie_iter_t* _it
    cdef readonly bint ordered

    def __cinit__(self, BaseTrie parent, bint ordered=False):
        self._parent = parent
        self.ordered = ordered

    def __dealloc__(self):
        if self._it != NULL:
            hattrie_iter_free(self._it)
            self._it = NULL
            self._parent = None

    def __iter__(self):
        return self

    def __next__(self):

        if self._parent is None:
            raise StopIteration

        elif self._it == NULL:
            self._it = hattrie_iter_begin(self._parent._trie, self.ordered)

        else:
            hattrie_iter_next(self._it)

        if hattrie_iter_finished(self._it):
            hattrie_iter_free(self._it)
            self._it = NULL
            self._parent = None
            raise StopIteration

        return self._nextvalue()

    def _nextvalue(self):
        cdef size_t c_keylen
        cdef char* c_key
        c_key = hattrie_iter_key(self._it, &c_keylen)
        return c_key[:c_keylen]


cdef class ValueIterable(Iterable):

    def _nextvalue(self):
        cdef value_t* value_ptr
        value_ptr = hattrie_iter_val(self._it)
        return self._parent._fromvalue(value_ptr[0])


cdef class ItemIterable(Iterable):

    def _nextvalue(self):
        cdef:
            size_t c_keylen
            char* c_key
            value_t* value_ptr
        c_key = hattrie_iter_key(self._it, &c_keylen)
        value_ptr = hattrie_iter_val(self._it)
        value = self._parent._fromvalue(value_ptr[0])
        return c_key[:c_keylen], value


cdef class BaseTrie:
    """
    HAT-Trie with unicode keys and int values.
    """

    cdef hattrie_t* _trie

    def __cinit__(self):
        self._trie = hattrie_create()

    def __dealloc__(self):
        if self._trie != NULL:
            hattrie_free(self._trie)
            self._trie = NULL

    def __delitem__(self, basestring key not None):
        cdef ssize_t c_keylen = len(key)
        cdef char* c_key = _asbytes(key)
        if hattrie_del(self._trie, c_key, c_keylen) != 0:
            raise KeyError(key)

    def __contains__(self, basestring key not None):
        return _tryget(self._trie, key) != NULL

    def __iter__(self):
        return self.iterkeys()

    def __len__(self):
        return hattrie_size(self._trie)

    def clear(self):
        hattrie_clear(self._trie)

    # TODO: Enable after implemented in C or remove.
    # def copy(self):
    #     new_trie = BaseTrie()
    #     new_trie._trie = hattrie_dup(self._trie)
    #     return new_trie

    def has_key(self, basestring key not None):
        return _tryget(self._trie, key) != NULL

    def iterkeys(self, bint ordered=False):
        return Iterable(self, ordered)

    def itervalues(self, bint ordered=False):
        return ValueIterable(self, ordered)

    def iteritems(self, bint ordered=False):
        return ItemIterable(self, ordered)

    if PY_MAJOR_VERSION >= 3:

        keys = iterkeys
        values = itervalues
        items = iteritems

    else:

        def keys(self, bint ordered=False):
            cdef:
                hattrie_iter_t* it
                size_t c_keylen
                char* c_key

            keylist = []
            it = hattrie_iter_begin(self._trie, ordered)
            while not hattrie_iter_finished(it):
                c_key = hattrie_iter_key(it, &c_keylen)
                keylist.append(<str> c_key[:c_keylen])
                hattrie_iter_next(it)

            hattrie_iter_free(it)
            return keylist

        def items(self, bint ordered=False):
            cdef:
                hattrie_iter_t* it
                size_t c_keylen
                char* c_key
                value_t* value_ptr

            itemlist = []
            it = hattrie_iter_begin(self._trie, ordered)
            while not hattrie_iter_finished(it):
                c_key = hattrie_iter_key(it, &c_keylen)
                value_ptr = hattrie_iter_val(it)
                item = <str> c_key[:c_keylen], self._fromvalue(value_ptr[0])
                itemlist.append(item)
                hattrie_iter_next(it)

            hattrie_iter_free(it)
            return itemlist

        def values(self, bint ordered=False):
            cdef:
                hattrie_iter_t* it
                value_t* value_ptr

            valuelist = []
            it = hattrie_iter_begin(self._trie, ordered)
            while not hattrie_iter_finished(it):
                value_ptr = hattrie_iter_val(it)
                valuelist.append(self._fromvalue(value_ptr[0]))
                hattrie_iter_next(it)

            hattrie_iter_free(it)
            return valuelist

    cdef _fromvalue(self, value_t value):
        return value


cdef class IntTrie(BaseTrie):
    """
    HAT-Trie with unicode support that stores int as value.
    """

    def __getitem__(self, basestring key not None):
        cdef value_t* value_ptr = _tryget(self._trie, key)
        if value_ptr == NULL:
            raise KeyError(key)
        return <long> value_ptr[0]

    def __setitem__(self, basestring key not None, long value):
        _set(self._trie, key, <value_t> value)

    def get(self, basestring key not None, value=None):
        cdef value_t* value_ptr = _tryget(self._trie, key)
        return value if value_ptr == NULL else (<long*> value_ptr)[0]

    def setdefault(self, basestring key not None, long value=0):
        return <long> _setdefault(self._trie, key, <value_t> value)

    cdef _fromvalue(self, value_t value):
        return <long> value


cdef class FloatTrie(BaseTrie):
    """
    HAT-Trie with unicode support that stores float as value.
    """

    def __getitem__(self, basestring key not None):
        cdef value_t* value_ptr = _tryget(self._trie, key)
        if value_ptr == NULL:
            raise KeyError(key)
        return (<double*> value_ptr)[0]

    def __setitem__(self, basestring key not None, double value):
        _set(self._trie, key, <value_t> (<value_t*> &value)[0])

    def get(self, basestring key not None, value=None):
        cdef value_t* value_ptr = _tryget(self._trie, key)
        return value if value_ptr == NULL else (<double*> value_ptr)[0]

    def setdefault(self, basestring key not None, double value=0.0):
        return <double> _setdefault(self._trie, key, (<value_t*> &value)[0])

    cdef _fromvalue(self, value_t value):
        return <double> value


cdef class Trie(BaseTrie):
    """
    HAT-Trie with unicode support and arbitrary values.
    """

    def __dealloc__(self):
        cdef hattrie_iter_t* it = hattrie_iter_begin(self._trie, 0)
        cdef cpython.PyObject *pyobj

        try:
            while not hattrie_iter_finished(it):
                pyobj = <cpython.PyObject*> hattrie_iter_val(it)[0]
                cpython.Py_XDECREF(pyobj)
                hattrie_iter_next(it)

        finally:
            hattrie_iter_free(it)

    def __getitem__(self, basestring key not None):
        cdef cpython.PyObject* pyobj
        cdef value_t* value_ptr = _tryget(self._trie, key)
        if value_ptr == NULL:
            raise KeyError(key)
        pyobj = <cpython.PyObject*> value_ptr[0]
        return <object> pyobj

    def __setitem__(self, basestring key not None, object value):
        cdef cpython.PyObject* pyobj
        cdef ssize_t c_keylen = len(key)
        cdef char* c_key = _asbytes(key)
        cdef value_t* value_ptr = hattrie_tryget(self._trie, c_key, c_keylen)
        if value_ptr != NULL:
            pyobj = <cpython.PyObject*> value_ptr[0]
            cpython.Py_XDECREF(pyobj)
        else:
            value_ptr = hattrie_get(self._trie, c_key, c_keylen)
        pyobj = <cpython.PyObject*> value
        cpython.Py_XINCREF(pyobj)
        value_ptr[0] = <value_t> pyobj

    def __delitem__(self, basestring key not None):
        cdef ssize_t c_keylen = len(key)
        cdef char* c_key = _asbytes(key)
        cdef value_t* value_ptr = hattrie_tryget(self._trie, c_key, c_keylen)
        if value_ptr == NULL or hattrie_del(self._trie, c_key, len(key)) != 0:
            raise KeyError(key)
        if value_ptr != NULL:
            cpython.Py_XDECREF(<cpython.PyObject*> value_ptr[0])

    def get(self, basestring key not None, value=None):
        cdef cpython.PyObject* pyobj
        cdef value_t* value_ptr = _tryget(self._trie, key)
        if value_ptr == NULL:
            return value
        pyobj = <cpython.PyObject*> value_ptr[0]
        return <object> pyobj

    def setdefault(self, basestring key not None, object value=None):
        cdef cpython.PyObject* pyobj
        cdef ssize_t c_keylen = len(key)
        cdef char* c_key = _asbytes(key)
        cdef value_t* value_ptr = hattrie_tryget(self._trie, c_key, c_keylen)
        if value_ptr != NULL:
            pyobj = <cpython.PyObject*> value_ptr[0]
            value = <object> pyobj
        else:
            pyobj = <cpython.PyObject*> value
            cpython.Py_XINCREF(pyobj)
            hattrie_get(self._trie, c_key, c_keylen)[0] = <value_t> pyobj
        return value

    cdef _fromvalue(self, value_t value):
        cdef cpython.PyObject* pyobj = <cpython.PyObject*> value
        return <object> pyobj
