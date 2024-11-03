"""Test our own built-in asserts"""

from common import TestQless


class TestAsserts(TestQless):
    """Ensure our own assert methods raise the exceptions they're supposed to"""

    def test_assertRaisesRegex(self):
        """Make sure that our home-brew assertRaisesRegex works"""

        def func():
            """Raises wrong error"""
            self.assertRaisesRegex(NotImplementedError, "base 10", int, "foo")

        self.assertRaises(ValueError, func)

        def func():
            """Doesn't match regex"""
            self.assertRaisesRegex(ValueError, "sklfjlskjflksjfs", int, "foo")

        self.assertRaises(AssertionError, func)
        self.assertRaises(ValueError, int, "foo")

        def func():
            """Doesn't throw any error"""
            self.assertRaisesRegex(ValueError, "base 10", int, 5)

        self.assertRaises(AssertionError, func)
