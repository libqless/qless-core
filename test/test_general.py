'''Check some general functionality surrounding the the API'''

from common import TestQless

class TestGeneral(TestQless):
    '''Some general tests'''
    def test_keys(self):
        '''No keys may be provided to the script'''
        self.assertRaises(Exception, self.lua.raw, 'foo')

    def test_unknown_function(self):
        '''If the API function is unknown, it should throw an error'''
        self.assertRaises(Exception, self.lua, 'foo')

    def test_no_time(self):
        '''If we neglect to provide a time, it should throw an error'''
        self.assertRaises(Exception, self.lua, 'put')

    def test_malformed_time(self):
        '''If we provide a non-numeric time, it should throw an error'''
        self.assertRaises(Exception, self.lua, 'put', 'foo')
