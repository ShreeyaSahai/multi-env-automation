pipeline {
    agent any

    environment {
        AWS_ACCESS_KEY_ID     = credentials('aws-access-key-id')
        AWS_SECRET_ACCESS_KEY = credentials('aws-secret-access-key')
        AWS_DEFAULT_REGION    = 'us-east-1'
        APP_VERSION           = 'v1.0.0'
    }

    stages {
        stage('Checkout SCM') {
            steps {
                checkout scm
            }
        }

        stage('Terraform Apply') {
            steps {
                dir('terraform') {
                    sh '''
                        terraform init -input=false
                        terraform apply -auto-approve -input=false
                        cp ../ansible/devops-key.pem /tmp/devops-key.pem
                        chmod 400 /tmp/devops-key.pem
                    '''
                }
            }
        }

        stage('Deploy to DEV via Ansible') {
            steps {
                dir('ansible') {
                    sh """
                        ansible-playbook -i inventory.ini deploy.yml \
                            -e "target_env=dev" \
                            -e "build_number=${env.BUILD_NUMBER}" \
                            -e "app_version=${env.APP_VERSION}"
                    """
                }
            }
        }

        stage('Smoke Test DEV') {
            steps {
                dir('terraform') {
                    sh '''
                        DEV_IP=$(terraform output -raw dev_public_ip)
                        echo "Running smoke test against DEV at http://${DEV_IP}/health"
                        for i in 1 2 3 4 5; do
                            if curl -sSf "http://${DEV_IP}/health" | grep -q "ok"; then
                                echo "DEV Smoke Test Passed!"
                                exit 0
                            fi
                            sleep 3
                        done
                        exit 1
                    '''
                }
            }
        }

        stage('Approval Gate') {
            steps {
                input message: 'Promote build to Production?', ok: 'Promote to PROD'
            }
        }

        stage('Deploy to PROD via Ansible') {
            steps {
                dir('ansible') {
                    sh """
                        ansible-playbook -i inventory.ini deploy.yml \
                            -e "target_env=prod" \
                            -e "build_number=${env.BUILD_NUMBER}" \
                            -e "app_version=${env.APP_VERSION}"
                    """
                }
            }
        }

        stage('Smoke Test PROD') {
            steps {
                dir('terraform') {
                    sh '''
                        PROD_IP=$(terraform output -raw prod_public_ip)
                        echo "Running smoke test against PROD at http://${PROD_IP}/health"
                        for i in 1 2 3 4 5; do
                            if curl -sSf "http://${PROD_IP}/health" | grep -q "ok"; then
                                echo "PROD Smoke Test Passed!"
                                echo "DEV URL:  http://$(terraform output -raw dev_public_ip)"
                                echo "PROD URL: http://${PROD_IP}"
                                exit 0
                            fi
                            sleep 3
                        done
                        exit 1
                    '''
                }
            }
        }
    }
}