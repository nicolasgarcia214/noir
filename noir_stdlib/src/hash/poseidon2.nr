global RATE = 3;

struct Poseidon2 {
    cache: [Field;3],
    state: [Field;4],
    cache_size: u32,
    squeeze_mode: bool, // 0 => absorb, 1 => squeeze
}

impl Poseidon2 {

    pub fn hash<N>(input: [Field; N], message_size: u32) -> Field {
        if message_size == N {
            Poseidon2::hash_internal(input, N, false)
        } else {
            Poseidon2::hash_internal(input, message_size, true)
        }
    }

    fn new(iv: Field) -> Poseidon2 {
        let mut result = Poseidon2 { cache: [0; 3], state: [0; 4], cache_size: 0, squeeze_mode: false };
        result.state[RATE] = iv;
        result
    }

    fn perform_duplex(&mut self) -> [Field; RATE] {
        // zero-pad the cache
        for i in 0..RATE {
            if i >= self.cache_size {
                self.cache[i] = 0;
            }
        }
        // add the cache into sponge state
        for i in 0..RATE {
            self.state[i] += self.cache[i];
        }
        self.state = crate::hash::poseidon2_permutation(self.state, 4);
        // return `RATE` number of field elements from the sponge state.
        let mut result = [0; RATE];
        for i in 0..RATE {
            result[i] = self.state[i];
        }
        result
    }

    fn absorb(&mut self, input: Field) {
        if (!self.squeeze_mode) & (self.cache_size == RATE) {
            // If we're absorbing, and the cache is full, apply the sponge permutation to compress the cache
            let _ = self.perform_duplex();
            self.cache[0] = input;
            self.cache_size = 1;
        } else if (!self.squeeze_mode) & (self.cache_size != RATE) {
            // If we're absorbing, and the cache is not full, add the input into the cache
            self.cache[self.cache_size] = input;
            self.cache_size += 1;
        } else if self.squeeze_mode {
            // If we're in squeeze mode, switch to absorb mode and add the input into the cache.
            // N.B. I don't think this code path can be reached?!
            self.cache[0] = input;
            self.cache_size = 1;
            self.squeeze_mode = false;
        }
    }

    fn squeeze(&mut self) -> Field {
        if self.squeeze_mode & (self.cache_size == 0) {
            // If we're in squeze mode and the cache is empty, there is nothing left to squeeze out of the sponge!
            // Switch to absorb mode.
            self.squeeze_mode = false;
            self.cache_size = 0;
        }
        if !self.squeeze_mode {
            // If we're in absorb mode, apply sponge permutation to compress the cache, populate cache with compressed
            // state and switch to squeeze mode. Note: this code block will execute if the previous `if` condition was
            // matched
            let new_output_elements = self.perform_duplex();
            self.squeeze_mode = true;
            for i in 0..RATE {
                self.cache[i] = new_output_elements[i];
            }
            self.cache_size = RATE;
        }
        // By this point, we should have a non-empty cache. Pop one item off the top of the cache and return it.
        let result = self.cache[0];
        for i in 1..RATE {
            if i < self.cache_size {
                self.cache[i - 1] = self.cache[i];
            }
        }
        self.cache_size -= 1;
        self.cache[self.cache_size] = 0;
        result
    }

    fn hash_internal<N>(input: [Field; N], in_len: u32, is_variable_length: bool) -> Field {
        let two_pow_64 = 18446744073709551616;
        let iv : Field = (in_len as Field) * two_pow_64;
        let mut sponge = Poseidon2::new(iv);
        for i in 0..input.len() {
            if i as u32 < in_len {
                sponge.absorb(input[i]);
            }
        }

        // In the case where the hash preimage is variable-length, we append `1` to the end of the input, to distinguish
        // from fixed-length hashes. (the combination of this additional field element + the hash IV ensures
        // fixed-length and variable-length hashes do not collide)
        if is_variable_length {
            sponge.absorb(1);
        }
        sponge.squeeze()
    }
}
