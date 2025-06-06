#!/usr/bin/env groovy

/*
 * Copyright (C) 2019 - present Instructure, Inc.
 *
 * This file is part of Canvas.
 *
 * Canvas is free software: you can redistribute it and/or modify it under
 * the terms of the GNU Affero General Public License as published by the Free
 * Software Foundation, version 3 of the License.
 *
 * Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
 * A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
 * details.
 *
 * You should have received a copy of the GNU Affero General Public License along
 * with this program. If not, see <http://www.gnu.org/licenses/>.
 */

library "canvas-builds-library@${env.CANVAS_BUILDS_REFSPEC}"
loadLocalLibrary('local-lib', 'build/new-jenkins/library')

pipeline {
  agent none
  options {
    ansiColor('xterm')
    timeout(time: 20)
    timestamps()
  }

  environment {
    BUILD_REGISTRY_FQDN = configuration.buildRegistryFQDN()
    COMPOSE_DOCKER_CLI_BUILD = 1
    COMPOSE_FILE = 'docker-compose.new-jenkins-js.yml'
    DOCKER_BUILDKIT = 1
    FORCE_FAILURE = commitMessageFlag('force-failure-js').asBooleanInteger()
    PROGRESS_NO_TRUNC = 1
    SELENIUM_NODE_IMAGE = '948781806214.dkr.ecr.us-east-1.amazonaws.com/docker.io/selenium/node-chromium:126.0-20240621'
    SELENIUM_HUB_IMAGE = '948781806214.dkr.ecr.us-east-1.amazonaws.com/docker.io/selenium/hub:4.22.0'
  }

  stages {
    stage('Environment') {
      steps {
        script {
          def hostSh = { script ->
            sh(script)
          }

          def postRunnerHandler = [
            onStageEnded: { stageName, stageConfig, result ->
              node('master') {
                buildSummaryReport.saveRunManifest()
              }
            }
          ]

          def stageHooks = [
            onNodeAcquired: { ->
              libraryScript.load('bash/docker-with-flakey-network-protection.sh', './docker-with-flakey-network-protection.sh')
              libraryScript.load('js/docker-provision.sh', './docker-provision.sh')

              hostSh('./docker-provision.sh')
            },
            onStageEnded: { stageName, stageConfig, result ->
              buildSummaryReport.setStageTimings(stageName, stageConfig.timingValues())
            }
          ]

          extendedStage('Runner').hooks(postRunnerHandler).obeysAllowStages(false).execute {
            def runnerStages = [:]
            def maxRandomizedJestShards = 5 // increased as tests become more stable

            for (int i = 0; i < maxRandomizedJestShards; i++) {
              String index = i
              extendedStage("Runner - Jest (randomized) ${i}").hooks(stageHooks).nodeRequirements(label: nodeLabel(), podTemplate: jsStage.jestNodeRequirementsTemplate(index)).obeysAllowStages(false).timeout(10).queue(runnerStages) {
                def tests = [:]
                callableWithDelegate(jsStage.queueRandomizedJestDistribution(index))(tests)
                parallel(tests)
              }
            }

            for (int i = maxRandomizedJestShards; i < jsStage.JEST_NODE_COUNT; i++) {
              String index = i
              extendedStage("Runner - Jest ${i}").hooks(stageHooks).nodeRequirements(label: nodeLabel(), podTemplate: jsStage.jestNodeRequirementsTemplate(index)).obeysAllowStages(false).timeout(10).queue(runnerStages) {
                def tests = [:]
                callableWithDelegate(jsStage.queueJestDistribution(index))(tests)
                parallel(tests)
              }
            }

            extendedStage('Runner - Packages').hooks(stageHooks).nodeRequirements(label: nodeLabel(), podTemplate: jsStage.packagesNodeRequirementsTemplate()).obeysAllowStages(false).timeout(12).queue(runnerStages) {
              def tests = [:]
              callableWithDelegate(jsStage.queuePackagesDistribution())(tests)
              parallel(tests)
            }

            parallel(runnerStages)
          }
        }
      }
    }
  }
}
