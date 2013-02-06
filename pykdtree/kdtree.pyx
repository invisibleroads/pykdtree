#pykdtree, Fast kd-tree implementation with OpenMP-enabled queries
# 
#Copyright (C) 2013  Esben S. Nielsen
#
#This program is free software: you can redistribute it and/or modify
#it under the terms of the GNU General Public License as published by
#the Free Software Foundation, either version 3 of the License, or
#(at your option) any later version.
#
#This program is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with this program.  If not, see <http://www.gnu.org/licenses/>.

import numpy as np
cimport numpy as np
from libc.stdint cimport uint32_t, int8_t
cimport cython


# Node structure
cdef struct node:
    double cut_val
    int8_t cut_dim
    uint32_t start_idx
    uint32_t n
    double cut_bounds_lv
    double cut_bounds_hv
    node *left_child
    node *right_child
    
cdef struct tree:
    double *bbox
    int8_t no_dims
    uint32_t *pidx
    node *root    
    

cdef extern tree* construct_tree(double *pa, int8_t no_dims, uint32_t n, uint32_t bsp) nogil
cdef extern void search_tree(tree *kdtree, double *pa, double *point_coords, uint32_t num_points, uint32_t k, double distance_upper_bound, double eps_fac, uint32_t *closest_idxs, double *closest_dists) nogil
cdef extern void delete_tree(tree *kdtree)

cdef class KDTree:
    """kd-tree for fast nearest-neighbour lookup.
    The interface is made to resemble the scipy.spatial kd-tree except
    only Euclidean distance measure is allowed.
    
    :Parameters:
    data_pts : numpy array
        Data points with shape (n , dims)
    leafsize : int, optional
        Maximum number of data points in tree leaf
    """

    cdef tree *_kdtree
    cdef np.ndarray _data_array
    cdef double *_data_array_data
    cdef uint32_t n
    cdef int8_t ndim
    cdef uint32_t leafsize
    
    def __init__(KDTree self, np.ndarray data_pts not None, int leafsize=10):

        # Check arguments
        if leafsize < 1:
            raise ValueError('leafsize must be greater than zero')    
        
        # Get data content
        cdef np.ndarray[double, ndim=1] data_array = np.ascontiguousarray(data_pts.ravel(), dtype=np.float64)
        self._data_array = data_array
        self._data_array_data = <double *>data_array.data
        
        # Get tree info
        self.n = <uint32_t>data_pts.shape[0]
        self.leafsize = <uint32_t>leafsize
        if data_pts.ndim == 1:
            self.ndim = 1
        else:
            self.ndim = <int8_t>data_pts.shape[1] 
        
        # Release GIL and construct tree
        with nogil:
            self._kdtree = construct_tree(self._data_array_data, self.ndim, 
                                          self.n, self.leafsize) 
        
    def query(KDTree self, np.ndarray query_pts not None, k=1, eps=0,
              distance_upper_bound=None, sqr_dists=False):
        """Query the kd-tree for nearest neighbors

        :Parameters:
        query_pts : numpy array
            Query points with shape (n , dims)
        k : int
            The number of nearest neighbours to return
        eps : non-negative float
            Return approximate nearest neighbours; the k-th returned value 
            is guaranteed to be no further than (1 + eps) times the distance 
            to the real k-th nearest neighbour
        distance_upper_bound : non-negative float
            Return only neighbors within this distance. 
            This is used to prune tree searches.
        sqr_dists : bool, optional
            Internally pykdtree works with squared distances. 
            Determines if the squared or Euclidean distances are returned.
        """
        
        # Check arguments
        if k < 1:
            raise ValueError('Number of neighbours must be greater than zero')
        elif eps < 0:
            raise ValueError('eps must be non-negative')
        elif distance_upper_bound is not None:
            if distance_upper_bound < 0:
                raise ValueError('distance_upper_bound must be non negative')
        
        # Check dimensions
        if query_pts.ndim == 1:
            q_ndim = 1
        else:
            q_ndim = query_pts.shape[1] 
        
        if self.ndim != q_ndim:
            raise ValueError('Data and query points must have same dimensions')
            
        # Get query points data        
        cdef np.ndarray[double, ndim=1] query_array = np.ascontiguousarray(query_pts.ravel(), dtype=np.float64)
        cdef double *query_array_data = <double *>query_array.data
        
        # Get query info
        cdef uint32_t num_qpoints = query_pts.shape[0]
        cdef uint32_t num_n = k
        cdef np.ndarray[uint32_t, ndim=1] closest_idxs = np.empty(num_qpoints * k, dtype=np.uint32)
        cdef np.ndarray[double, ndim=1] closest_dists = np.empty(num_qpoints * k, dtype=np.float64)
                
        # Set up return arrays
        cdef uint32_t *closest_idxs_data = <uint32_t *>closest_idxs.data
        cdef double *closest_dists_data = <double *>closest_dists.data
    
        # Setup distance_upper_bound
        cdef double dub
        if distance_upper_bound is None:
            dub = <double>np.finfo(np.float64).max    
        else:
            dub = <double>(distance_upper_bound * distance_upper_bound)
        
        # Set epsilon        
        cdef double epsilon = <double>eps        
        
        # Release GIL and query tree
        with nogil:
            search_tree(self._kdtree, self._data_array_data, 
                        query_array_data, num_qpoints, num_n, dub, epsilon, 
                        closest_idxs_data, closest_dists_data)
        
        # Shape result
        if k > 1:
            closest_dists_res = closest_dists.reshape(num_qpoints, k)
            closest_idxs_res = closest_idxs.reshape(num_qpoints, k)
        else:
            closest_dists_res = closest_dists
            closest_idxs_res = closest_idxs

        if distance_upper_bound is not None: # Mark out of bounds results
            idx_out = (closest_dists_res >= dub)
            closest_dists_res[idx_out] = np.Inf
            closest_idxs_res[idx_out] = self.n
            
        if not sqr_dists: # Return actual cartesian distances
            closest_dists_res = np.sqrt(closest_dists_res)
            
        return closest_dists_res, closest_idxs_res
    
    def __dealloc__(KDTree self):
        if <int>(self._kdtree) == 0:
            # should happen only if __init__ was never called
            return
        delete_tree(self._kdtree)
        

    
                        
            
    

    

