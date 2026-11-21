#!/bin/zsh
set -eu
cd "${0:A:h:h}"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
TASK_TEST_DIR=$(mktemp -d /tmp/optitag-contracts.XXXXXX)
trap 'rm -rf "$TASK_TEST_DIR"' EXIT
swiftc -module-cache-path "$TASK_TEST_DIR/cache" optiTAG/Recognition/EventCSV.swift Tests/CSVContractChecks.swift -o "$TASK_TEST_DIR/csv"
"$TASK_TEST_DIR/csv"
swiftc -module-cache-path "$TASK_TEST_DIR/cache" optiTAG/Database/OptiTagDatabase.swift optiTAG/Models/Person.swift optiTAG/Models/RecognitionLog.swift Tests/PeopleContractChecks.swift -o "$TASK_TEST_DIR/people"
"$TASK_TEST_DIR/people"
swiftc -module-cache-path "$TASK_TEST_DIR/cache" optiTAG/Recognition/ConversationModels.swift optiTAG/Recognition/ConversationAudioCleanup.swift optiTAG/Recognition/ConversationRepository.swift Tests/ConversationRepositoryChecks.swift -o "$TASK_TEST_DIR/conversations"
"$TASK_TEST_DIR/conversations"
swiftc -module-cache-path "$TASK_TEST_DIR/cache" optiTAG/Recognition/EventMetadata.swift Tests/EventMetadataChecks.swift -o "$TASK_TEST_DIR/metadata"
"$TASK_TEST_DIR/metadata"
swiftc -module-cache-path "$TASK_TEST_DIR/cache" optiTAG/Recognition/GoogleSpeechFailure.swift Tests/GoogleSpeechFailureChecks.swift -o "$TASK_TEST_DIR/google-errors"
"$TASK_TEST_DIR/google-errors"
