# Copyright (C) 2009 Canonical Ltd
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA

"""The core routines for scanning python references and dumping memory info."""

cdef extern from "stdio.h":
    ctypedef long size_t
    ctypedef struct FILE:
        pass
    size_t fwrite(void *, size_t, size_t, FILE *)
    size_t fprintf(FILE *, char *, ...)

cdef extern from "Python.h":
    struct _typeobject:
        char * tp_name
        Py_ssize_t tp_basicsize
        Py_ssize_t tp_itemsize

    ctypedef struct PyObject:
        Py_ssize_t ob_refcnt
        _typeobject *ob_type

    ctypedef struct PyVarObject:
        Py_ssize_t ob_refcnt
        _typeobject *ob_type
        Py_ssize_t ob_size

    ctypedef struct PyListObject:
        Py_ssize_t ob_refcnt
        _typeobject *ob_type
        Py_ssize_t allocated

    ctypedef struct setentry:
        pass

    ctypedef struct PySetObject:
        Py_ssize_t ob_refcnt
        _typeobject *ob_type
        Py_ssize_t mask
        setentry *table
        setentry *smalltable

    ctypedef struct PyDictEntry:
        pass

    ctypedef struct PyDictObject:
        Py_ssize_t ob_refcnt
        _typeobject *ob_type
        Py_ssize_t ma_mask
        Py_ssize_t ma_table
        Py_ssize_t ma_smalltable

    ctypedef struct PyUnicodeObject:
        Py_ssize_t ob_refcnt
        _typeobject *ob_type
        Py_ssize_t length

    FILE *PyFile_AsFile(object)

    int Py_UNICODE_SIZE

    int PyList_Check(PyObject *)
    int PyAnySet_Check(PyObject *)
    int PyDict_Check(PyObject *)
    int PyUnicode_Check(PyObject *)


cdef Py_ssize_t _basic_object_size(PyObject *c_obj):
    return c_obj.ob_type.tp_basicsize


cdef Py_ssize_t _var_object_size(PyVarObject *c_obj):
    return (c_obj.ob_type.tp_basicsize +
            c_obj.ob_size * c_obj.ob_type.tp_itemsize)


cdef Py_ssize_t _size_of_list(PyListObject *c_obj):
    cdef Py_ssize_t size
    size = _basic_object_size(<PyObject *>c_obj)
    size += sizeof(PyObject*) * c_obj.allocated
    return size


cdef Py_ssize_t _size_of_set(PySetObject *c_obj):
    cdef Py_ssize_t size
    size = _basic_object_size(<PyObject *>c_obj)
    if c_obj.table != c_obj.smalltable:
        size += sizeof(setentry) * (c_obj.mask + 1)
    return size


cdef Py_ssize_t _size_of_dict(PyDictObject *c_obj):
    cdef Py_ssize_t size
    size = _basic_object_size(<PyObject *>c_obj)
    if c_obj.ma_table != c_obj.ma_smalltable:
        size += sizeof(PyDictEntry) * (c_obj.ma_mask + 1)
    return size


cdef Py_ssize_t _size_of_unicode(PyUnicodeObject *c_obj):
    cdef Py_ssize_t size
    size = _basic_object_size(<PyObject *>c_obj)
    size += Py_UNICODE_SIZE * c_obj.length
    return size

_word_size = sizeof(Py_ssize_t)
_unicode_size = Py_UNICODE_SIZE


cdef Py_ssize_t _size_of(PyObject *c_obj):
    if PyList_Check(c_obj):
        return _size_of_list(<PyListObject *>c_obj)
    elif PyAnySet_Check(c_obj):
        return _size_of_set(<PySetObject *>c_obj)
    elif PyDict_Check(c_obj):
        return _size_of_dict(<PyDictObject *>c_obj)
    elif PyUnicode_Check(c_obj):
        return _size_of_unicode(<PyUnicodeObject *>c_obj)

    if c_obj.ob_type.tp_itemsize != 0:
        # Variable length object with inline storage
        # total size is tp_itemsize * ob_size
        return _var_object_size(<PyVarObject *>c_obj)
    return _basic_object_size(c_obj)


def size_of(obj):
    """Compute the size of the object.

    This is the actual malloc() size for this object, so for dicts it is the
    size of the dict object, plus the size of the array of references, but
    *not* the size of each individual referenced object.

    :param obj: The object to measure
    :return: An integer of the number of bytes used by this object.
    """
    cdef PyObject *c_obj

    c_obj = <PyObject *>obj
    return _size_of(c_obj)


cdef void _dump_object_info(FILE *out, PyObject * c_obj):
    cdef Py_ssize_t size

    size = _size_of(c_obj)
    fprintf(out, "%08lx %s %d", <long>c_obj, c_obj.ob_type.tp_name,
                                size)
    fprintf(out, "\n")


def dump_object_info(object fp, object obj):
    cdef FILE *out

    out = PyFile_AsFile(fp)
    if out == NULL:
        raise TypeError('not a file')
    _dump_object_info(out, <PyObject *>obj)
