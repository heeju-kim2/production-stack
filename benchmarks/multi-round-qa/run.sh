#!/bin/bash

if [[ $# -ne 3 ]]; then
    echo "Usage: $0 <model> <base url> <save file key>"
    exit 1
fi

# vllm serve meta-llama/Llama-3.1-8B-Instruct --no-enable-prefix-caching 
# bash run.sh meta-llama/Llama-3.1-8B-Instruct http://localhost:8000/v1 naive 
# bash run.sh furiosa-ai/Llama-3.1-8B-Instruct http://localhost:8000/v1 naive

MODEL=$1
BASE_URL=$2
# Warmup: precompute KV and store inside CPU mem
# CONFIGURATION
NUM_USERS_WARMUP=100 #400

SYSTEM_PROMPT=100 # Shared system prompt length
CHAT_HISTORY=900 # User specific chat history length
ANSWER_LEN=1000 # Generation length per round

warmup() {
    # Warm up the vLLM with a lot of user queries
    python3 ./multi-round-qa.py \
        --num-users 1 \
        --num-rounds 2 \
        --qps 2 \
        --shared-system-prompt $SYSTEM_PROMPT \
        --user-history-prompt $CHAT_HISTORY \
        --answer-len $ANSWER_LEN \
        --model "$MODEL" \
        --base-url "$BASE_URL" \
        --output /tmp/warmup.csv \
        --log-interval 30 \
        --time $((NUM_USERS_WARMUP / 2))
}

warmup


MODEL=$1
BASE_URL=$2

# CONFIGURATION
NUM_USERS=320
NUM_ROUNDS=2

SYSTEM_PROMPT=100 # Shared system prompt length

run_benchmark() {
    # $1: qps
    # $2: output dir

    # Real run
    python3 ./multi-round-qa.py \
        --num-users $NUM_USERS \
        --num-rounds $NUM_ROUNDS \
        --qps "$1" \
        --shared-system-prompt "$SYSTEM_PROMPT" \
        --user-history-prompt "$CHAT_HISTORY" \
        --answer-len $ANSWER_LEN \
        --model "$MODEL" \
        --base-url "$BASE_URL" \
        --output_dir "$2" \
        --log-interval 30 \
        --time 100

    sleep 10
}

KEY=$3

# Run benchmarks for different QPS values

if [[ "$KEY" == "naive" ]]; then
    QPS_VALUES=(0.1 0.5 0.9 1.3 1.7 2.1 2.5 2.9 3.3 3.7 4.1 4.5 4.9 5.3 5.7 6.1 6.5 6.9 7.3 7.7 8.1 8.5 8.9 9.3 9.7 10.1 15.0 20.0 30.0 40.0 50.0 60.0 70.0 80.0 90.0 100.0)
    ANSWER_LEN=(100) #300 500 700 900)
    CHAT_HISTORY=(1100) #(500 700 900 1100)
else
    QPS_VALUES=(1) # 2 3 4 5 6) #(4.1 3.7 3.3 2.9 2.5 2.1 1.7 1.3 0.9 0.5 0.1)
fi

# Run benchmarks for the determined QPS values

for answer_len in "${ANSWER_LEN[@]}"; do
    for chat_history in "${CHAT_HISTORY[@]}"; do
        for qps in "${QPS_VALUES[@]}"; do
            output_dir="${KEY}_output_${SYSTEM_PROMPT}_${chat_history}_${answer_len}_${qps}"
            ANSWER_LEN=$answer_len # Generation length per round 
            CHAT_HISTORY=$chat_history # User specific chat history length
            echo "Running benchmark with QPS: $qps, Answer Length: $ANSWER_LEN, Chat History: $CHAT_HISTORY, Output Dir: $output_dir"
            run_benchmark "$qps" "$output_dir"
        done
    done
done
