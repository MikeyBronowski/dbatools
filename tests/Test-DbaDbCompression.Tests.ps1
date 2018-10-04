﻿$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 10
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Test-DbaDbCompression).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential','Database','ExcludeDatabase','Schema','Table','ResultSize','Rank','FilterBy', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        Get-DbaProcess -SqlInstance $script:instance2 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
        $dbname = "dbatoolsci_test_$(get-random)"
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $null = $server.Query("Create Database [$dbname]")
        $null = $server.Query("Create Schema test",$dbname)
        $null = $server.Query(" select * into syscols from sys.all_columns
                                select * into test.sysallparams from sys.all_parameters
                                create clustered index CL_sysallparams on test.sysallparams (object_id)
                                create nonclustered index NC_syscols on syscols (precision) include (collation_name)
                                update test.sysallparams set is_xml_document = 1 where name = '@dbname'
                                ",$dbname)
       }
    AfterAll {
        Get-DbaProcess -SqlInstance $script:instance2 -Database $dbname | Stop-DbaProcess -WarningAction SilentlyContinue
        Remove-DbaDatabase -SqlInstance $script:instance2 -Database $dbname -Confirm:$false
    }
    Context "Command gets suggestions" {
        $results = Test-DbaDbCompression -SqlInstance $script:instance2 -Database $dbname
        It "Should get results for $dbaname" {
            $results | Should Not Be $null
        }
        $results.foreach{
            It "Should suggest ROW, PAGE or NO_GAIN for $($PSitem.TableName) - $($PSitem.IndexType) " {
                $PSitem.CompressionTypeRecommendation | Should BeIn ("ROW","PAGE","NO_GAIN")
            }
            It "Should have values for PercentScan and PercentUpdate  $($PSitem.TableName) - $($PSitem.IndexType) " {
                $PSitem.PercentUpdate | Should Not BeNullOrEmpty
                $PSitem.PercentScan | Should Not BeNullOrEmpty
            }
        }
    }
    Context "Command makes right suggestions" {
        $results = Test-DbaDbCompression -SqlInstance $script:instance2 -Database $dbname
        It "Should sugggest PAGE compression for a table with no updates or scans" {
            $($results | Where-Object { $_.TableName -eq "syscols" -and $_.IndexType -eq "HEAP"}).CompressionTypeRecommendation | Should Be "PAGE"
        }
        It "Should sugggest ROW compression for table with more updates" {
            $($results | Where-Object { $_.TableName -eq "sysallparams"}).CompressionTypeRecommendation | Should Be "ROW"
        }
    }
    Context "Command excludes results for specified database" {
        It "Shouldn't get any results for $dbname" {
            $(Test-DbaDbCompression -SqlInstance $script:instance2 -Database $dbname -ExcludeDatabase $dbname).Database | Should not Match $dbname
        }
    }
    Context "Command gets Schema suggestions" {
        $schema = 'dbo'
        $results = Test-DbaDbCompression -SqlInstance $script:instance2 -Database $dbname -Schema $schema
        It "Should get results for Schema:$schema" {
            $results | Should Not Be $null
        }
    }
    Context "Command gets Table suggestions" {
        $table = 'syscols'
        $results = Test-DbaDbCompression -SqlInstance $script:instance2 -Database $dbname -Table $table
        It "Should get results for table:$table" {
            $results | Should Not Be $null
        }
    }
    Context "Command gets limited output" {
        $resultCount = 2
        $results = Test-DbaDbCompression -SqlInstance $script:instance2 -Database $dbname -ResultSize $resultCount -Rank TotalPages -FilterBy Partition
        It "Should get only $resultCount results" {
            $results.Count | Should Be $resultCount
        }
    }
}