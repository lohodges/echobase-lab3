pipeline {
    agent any

    environment {
        AWS_DEFAULT_REGION = 'ap-northeast-1'
        TF_IN_AUTOMATION   = 'true'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }
 
        stage('Terraform Init') {
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'jenkinsProd'
                ]]) {
                    sh '''
                        terraform -chdir=saopaulo init
                        terraform -chdir=tokyo init
                        terraform -chdir=interlink init
                    '''
                }
            }
        }

        stage('Deploy Saopaulo & Tokyo') {
            parallel {
                stage('Deploy Saopaulo') {
                    steps {
                        withCredentials([[
                            $class: 'AmazonWebServicesCredentialsBinding',
                            credentialsId: 'jenkinsProd'
                        ]]) {
                            sh '''
                                terraform -chdir=saopaulo plan -out=tfplan
                                terraform -chdir=saopaulo apply -auto-approve tfplan
                            '''
                        }
                    }
                }
                stage('Deploy Tokyo') {
                    steps {
                        withCredentials([[
                            $class: 'AmazonWebServicesCredentialsBinding',
                            credentialsId: 'jenkinsProd'
                        ]]) {
                            sh '''
                                terraform -chdir=tokyo plan -out=tfplan
                                terraform -chdir=tokyo apply -auto-approve tfplan
                            '''
                        }
                    }
                }
            }
        }

        stage('Deploy Interlink') {
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'jenkinsProd'
                ]]) {
                    sh '''
                        terraform -chdir=interlink plan -out=tfplan
                        terraform -chdir=interlink apply -auto-approve tfplan
                    '''
                }
            }
        }

        stage('Optional Destroy') {
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'jenkinsProd'
                ]]) {
                    script {
                        def destroyChoice = input(
                            message: 'Do you want to run terraform destroy?',
                            ok: 'Submit',
                            parameters: [
                                choice(
                                    name: 'DESTROY',
                                    choices: ['no', 'yes'],
                                    description: 'Select yes to destroy resources'
                                )
                            ]
                        )
                        if (destroyChoice == 'yes') {
                            sh 'terraform -chdir=interlink destroy -auto-approve'
                            sh 'terraform -chdir=saopaulo destroy -auto-approve'
                            sh 'terraform -chdir=tokyo destroy -auto-approve'
                        } else {
                            echo "Skipping destroy"
                        }
                    }
                }
            }
        }
    }
}