import * as core from '@aws-cdk/core'
import * as codeartifact from '@aws-cdk/aws-codeartifact'
import { CfnOutput, RemovalPolicy } from '@aws-cdk/core';

// For Code Artifacts
export class CodeArtifactResources extends core.Stack {
    constructor(scope: core.App, id: string) {
        super(scope, id)

        const domain = new codeartifact.CfnDomain(this, 'CodeArtifactDomain', {
            domainName: 'reinvent-domain-2021'
        })
        const pyRepo = new codeartifact.CfnRepository(this, 'pyRepository', {
            domainName:domain.domainName,
            repositoryName: 'reinvent-repository-2021',
            externalConnections: [
                'public:pypi'
            ]
        })
        pyRepo.addOverride('Properties.DomainName', domain.domainName)
        pyRepo.addDependsOn(domain)
        const npmRepo = new codeartifact.CfnRepository(this, 'npmRepo', {
             domainName:domain.domainName,
            repositoryName: 'npmRepo',
            externalConnections: [
                'public:npmjs'
            ]
        })
        npmRepo.addOverride('Properties.DomainName', domain.domainName)
        npmRepo.addDependsOn(domain)
        const workshopRepo = new codeartifact.CfnRepository(this, 'workshopRepo', {
             domainName:domain.domainName,
            repositoryName: 'workshop-repository',
            upstreams: [
                npmRepo.repositoryName,
                pyRepo.repositoryName
            ]
        })
        workshopRepo.addOverride('Properties.DomainName', domain.domainName)
        workshopRepo.addDependsOn(npmRepo)
        workshopRepo.addDependsOn(pyRepo)
        new CfnOutput(this,"domainName",{ value: domain.domainName})
        new CfnOutput(this,"repositoryName",{ value: workshopRepo.repositoryName})
    }
}
const app = new core.App()
new CodeArtifactResources(app, 'CodeArtifactResources')