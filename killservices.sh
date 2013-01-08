#!/bin/bash

for X in `cat data/worker.pids`; do
	kill $X
done
