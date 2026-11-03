package com.ezequielbrrt.domemory.services

import com.ezequielbrrt.domemory.services.levels.Stars
import org.junit.Assert.assertEquals
import org.junit.Test

class StarsTest {

    @Test
    fun `three stars need both half the clock and at most one mistake`() {
        assertEquals(3, Stars.award(timeRemaining = 50.0, totalTime = 100.0, failedTries = 0))
        assertEquals(3, Stars.award(timeRemaining = 90.0, totalTime = 100.0, failedTries = 1))
        // Fast but sloppy is two stars, not three.
        assertEquals(2, Stars.award(timeRemaining = 90.0, totalTime = 100.0, failedTries = 2))
    }

    @Test
    fun `two stars at a quarter of the clock`() {
        assertEquals(2, Stars.award(timeRemaining = 25.0, totalTime = 100.0, failedTries = 0))
        assertEquals(2, Stars.award(timeRemaining = 49.0, totalTime = 100.0, failedTries = 0))
    }

    @Test
    fun `one star otherwise, including a clean but slow clear`() {
        assertEquals(1, Stars.award(timeRemaining = 24.0, totalTime = 100.0, failedTries = 0))
        assertEquals(1, Stars.award(timeRemaining = 0.0, totalTime = 100.0, failedTries = 9))
    }

    @Test
    fun `a zero total time cannot divide by zero`() {
        assertEquals(1, Stars.award(timeRemaining = 0.0, totalTime = 0.0, failedTries = 0))
    }
}
